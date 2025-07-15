//
//  DockerOrchestrator.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor DockerOrchestrator {
    private let workingDirectory: URL
    private let composeFile: String
    
    private(set) var isRunning = false
    private(set) var paperlessUrl: URL?
    
    struct TestConfiguration: Sendable {
        let superUserUsername = "admin"
        let superUserPassword = "admin"
        let superUserEmail = "admin@example.com"
        let port = 8080
        
        var url: URL {
            URL(string: "http://localhost:\(port)")!
        }
    }
    
    let config = TestConfiguration()
    
    init() throws {
        // Find the demo directory relative to the package
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        
        // Try to find demo directory - could be in current dir or parent dirs
        var searchDir = currentDirectory
        var demoDir: URL?
        
        for _ in 0..<5 { // Search up to 5 levels up
            let candidateDemo = searchDir.appendingPathComponent("demo")
            if FileManager.default.fileExists(atPath: candidateDemo.path) {
                demoDir = candidateDemo
                break
            }
            searchDir = searchDir.deletingLastPathComponent()
        }
        
        guard let demoDirectory = demoDir else {
            throw DockerError.projectRootNotFound
        }
        
        self.workingDirectory = demoDirectory
        self.composeFile = "docker-compose.yml"
        
        print("Docker orchestrator working directory: \(workingDirectory.path)")
    }
    
    enum DockerError: Error, LocalizedError, CustomStringConvertible {
        case projectRootNotFound
        case dockerNotAvailable
        case composeUpFailed(String)
        case composeDownFailed(String)
        case healthCheckFailed
        case superUserCreationFailed(String)
        
        var errorDescription: String? { description }
        
        var description: String {
            switch self {
            case .projectRootNotFound:
                return "Could not find project root directory with demo folder"
            case .dockerNotAvailable:
                return "Docker is not available or not running"
            case .composeUpFailed(let output):
                return "Docker compose up failed: \(output)"
            case .composeDownFailed(let output):
                return "Docker compose down failed: \(output)"
            case .healthCheckFailed:
                return "Health check failed - Paperless instance is not responding"
            case .superUserCreationFailed(let output):
                return "Failed to create superuser: \(output)"
            }
        }
    }
    
    func startPaperlessInstance() async throws {
        guard !isRunning else { return }
        
        print("Starting Paperless-ngx test instance...")
        
        // Check if Docker is available
        try await checkDockerAvailability()
        
        // Stop any existing containers
        try await stopPaperlessInstance()
        
        // Start the containers
        try await runDockerCompose(["up", "-d"])
        
        // Wait for the instance to be healthy
        try await waitForHealthy()
        
        // Create superuser
        try await createSuperUser()
        
        isRunning = true
        paperlessUrl = config.url
        
        print("Paperless-ngx test instance started successfully at \(config.url)")
    }
    
    func stopPaperlessInstance() async throws {
        print("Stopping Paperless-ngx test instance...")
        
        do {
            try await runDockerCompose(["down", "-v", "--remove-orphans"])
            print("Paperless-ngx test instance stopped")
        } catch {
            print("Warning: Failed to stop containers cleanly: \(error)")
            // Continue anyway - we want to ensure cleanup
        }
        
        isRunning = false
        paperlessUrl = nil
    }
    
    private func checkDockerAvailability() async throws {
        let result = try await runProcess(executable: "/usr/bin/env", arguments: ["docker", "--version"])
        
        if result.exitCode != 0 {
            throw DockerError.dockerNotAvailable
        }
    }
    
    private func runDockerCompose(_ arguments: [String]) async throws {
        let result = try await runProcess(
            executable: "/usr/bin/env", 
            arguments: ["docker", "compose", "-f", composeFile] + arguments,
            workingDirectory: workingDirectory
        )
        
        print("Running: docker compose \(arguments.joined(separator: " "))")
        
        if result.exitCode != 0 {
            print("Docker compose failed with exit code \(result.exitCode)")
            print("Output: \(result.output)")
            
            if arguments.first == "up" {
                throw DockerError.composeUpFailed(result.output)
            } else if arguments.first == "down" {
                throw DockerError.composeDownFailed(result.output)
            }
        } else {
            print("Docker compose output: \(result.output)")
        }
    }
    
    private func waitForHealthy(timeout: TimeInterval = 120) async throws {
        let startTime = Date()
        print("Waiting for Paperless instance to become healthy...")
        
        while Date().timeIntervalSince(startTime) < timeout {
            do {
                let (_, response) = try await URLSession.shared.data(from: config.url.appendingPathComponent("api/"))
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    print("Paperless instance is healthy")
                    return
                }
            } catch {
                // Expected while starting up
            }
            
            print("Waiting for instance to be ready...")
            try await Task.sleep(for: .seconds(2))
        }
        
        throw DockerError.healthCheckFailed
    }
    
    private func createSuperUser() async throws {
        print("Creating superuser...")
        
        var environment = ProcessInfo.processInfo.environment
        environment["DJANGO_SUPERUSER_PASSWORD"] = config.superUserPassword
        
        let result = try await runProcess(
            executable: "/usr/bin/env",
            arguments: [
                "docker", "compose", "-f", composeFile, "exec", "-T", "webserver",
                "python3", "manage.py", "createsuperuser",
                "--noinput",
                "--username", config.superUserUsername,
                "--email", config.superUserEmail
            ],
            workingDirectory: workingDirectory,
            environment: environment
        )
        
        if result.exitCode != 0 && !result.output.contains("already exists") {
            print("Superuser creation failed: \(result.output)")
            throw DockerError.superUserCreationFailed(result.output)
        }
        
        print("Superuser created successfully")
    }
    
    func createAdditionalUser(username: String, password: String, email: String, isStaff: Bool = false) async throws {
        print("Creating additional user: \(username)")
        
        let shellCommand = """
            from django.contrib.auth import get_user_model;
            User = get_user_model();
            user, created = User.objects.get_or_create(username='\(username)', defaults={'email': '\(email)', 'is_staff': \(isStaff)});
            user.set_password('\(password)');
            user.save();
            print(f'User {user.username} {"created" if created else "updated"}')
            """
        
        let result = try await runProcess(
            executable: "/usr/bin/env",
            arguments: [
                "docker", "compose", "-f", composeFile, "exec", "-T", "webserver",
                "python3", "manage.py", "shell", "-c", shellCommand
            ],
            workingDirectory: workingDirectory
        )
        
        if result.exitCode != 0 {
            print("User creation failed: \(result.output)")
            throw DockerError.superUserCreationFailed(result.output)
        }
        
        print("User \(username) created successfully")
    }
    
    // MARK: - Process execution helpers
    
    private struct ProcessResult {
        let exitCode: Int32
        let output: String
    }
    
    private func runProcess(
        executable: String, 
        arguments: [String], 
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            
            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }
            
            if let environment = environment {
                process.environment = environment
            }
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                let result = ProcessResult(exitCode: process.terminationStatus, output: output)
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    deinit {
        // Cleanup in case tests don't call stop explicitly
        if isRunning {
            Task {
                try? await stopPaperlessInstance()
            }
        }
    }
}