import AuthenticationServices
import Common
import CryptoKit
import SwiftUI
import UIKit
import Networking

struct ContentView: View {
  @Environment(\.webAuthenticationSession) private var auth
  
  private let redirectURL = URL(string: "x-oauth-test://callback")!
  private let backendURL = URL(string: "http://localhost:8000")!
  
  @State private var client : OIDCClient
  
  init() {
    _client = try! State(initialValue: OIDCClient(baseURL: backendURL, redirectURI: redirectURL))
    
  }

  var body: some View {
    Form {
      Section {
        Text(client.token ?? "idle").font(.footnote)
      }
      
      if !client.providers.isEmpty {
        Button("Login") { Task { try? await client.login(provider: client.providers[0], auth: auth) } }
      }
      Section("Providers") {
        if client.providers.isEmpty {
          Button("Fetch providers") { Task { try? await client.fetchProviders() } }
        }
        else {
          ForEach(client.providers) { provider in
            LabeledContent("Provider") {
              Text(provider.openidConfigurationUrl)
              Text("ID: \(provider.id)")
            }
          }
        }
      }
    }
  }
}

@main
struct PaperlessOIDCExampleApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
