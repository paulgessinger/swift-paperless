//
//  MTLSCertificateView.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import SwiftUI


enum CertificateState {
    case notloaded
    case wrongPassword
    case valid
}

struct MTLSSettingsView: View {
    
    @State private var certificatePassword: String = ""
    @State private var certificateName: String = ""
    @State private var certificateData: Data? = nil
    
    @State private var isImporting: Bool = false
    @State private var isCertificateValid = false
    @State private var certificateState: CertificateState = .notloaded
    
    
    
    private func validateCertificate(certificateData: Data, certificatePassword: String) -> Bool {
        do {
            let _ = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
            return true
        } catch {
            
        }
        return false
    }
    
    private func saveToKeychain(certificateData: Data, certificatePassword: String){
        do {
            let pkc = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
            if let identity = pkc.identity {
                Keychain.saveIdentity(identity: identity, name: "User_Certificate")
            }
        }catch {
            print(error)
        }
        
    }
    
    var body: some View {
        Form {
            Section {
                TextField("Certificate Name", text: $certificateName).disabled(true)
                SecureField("Certificate Password",text: $certificatePassword).autocorrectionDisabled()
                Button("Select Certificate"){
                    self.isImporting = true
                }
            } footer: {
                switch certificateState {
                case .notloaded:
                    Text("No Certificate loaded")
                case .wrongPassword:
                    Text("Cant´t load. Wrong password?")
                case .valid:
                    HStack{
                        Image("checkmark.circle.fill")
                        Text("Valid")
                    }
                }
            }
            
            Section {
                Button("Save"){
                    guard let data = certificateData else {
                        isCertificateValid = false
                        certificateState = .notloaded
                        return
                    }
                    saveToKeychain(certificateData: data, certificatePassword: certificatePassword)
                }.disabled(!isCertificateValid)
                
            }
        }
        .onChange(of: certificateData){
            guard let data = certificateData else {
                isCertificateValid = false
                certificateState = .notloaded
                return
            }
            if validateCertificate(certificateData: data, certificatePassword: certificatePassword) {
                certificateState = .valid
                isCertificateValid = true
            }else {
                certificateState = .wrongPassword
                isCertificateValid = false
            }
        }
        .onChange(of: certificatePassword){
            guard let data = certificateData else {
                isCertificateValid = false
                certificateState = .notloaded
                return
            }
            if validateCertificate(certificateData: data, certificatePassword: certificatePassword) {
                certificateState = .valid
                print("Certificate set valid")
                isCertificateValid = true
            }else {
                certificateState = .wrongPassword
                print("Certificate set invalid")
                isCertificateValid = false
            }
        }
        .onChange(of: certificateData){
            guard let data = certificateData else {
                isCertificateValid = false
                certificateState = .notloaded
                return
            }
            if validateCertificate(certificateData: data, certificatePassword: certificatePassword) {
                certificateState = .valid
                print("Certificate set valid")
                isCertificateValid = true
            }else {
                certificateState = .wrongPassword
                print("Certificate set invalid")
                isCertificateValid = false
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pkcs12],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile: URL = try result.get().first else { return }
                if selectedFile.startAccessingSecurityScopedResource() {
                    self.certificateData = try Data(contentsOf: selectedFile)
                    defer { selectedFile.stopAccessingSecurityScopedResource() }
                    self.certificateName = selectedFile.lastPathComponent
                } else {
                    print("File access denied")
                }
            } catch {
                
                print("Unable to read file contents")
                print(error.localizedDescription)
            }
        }
    }
}
