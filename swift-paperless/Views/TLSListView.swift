//
//  TLSListView.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import os
import SwiftUI

private struct TLSIdentity: Identifiable, Equatable {
    var name: String
    var identity: SecIdentity

    var id: String { name }
}

private enum CertificateState {
    case notloaded
    case wrongPassword
    case valid
    case loadingError(String)
}

struct TLSListView: View {
    @State private var identities: [TLSIdentity] = []
    @State private var identityNames: [String] = []
    @State private var showCreate: Bool = false

    @EnvironmentObject private var errorController: ErrorController

    private func refreshAll() {
        let keyChainIdenitites: [(SecIdentity, String)] = Keychain.readAllIdenties()

        let pIdentityNames: [String] = keyChainIdenitites.map { _, name in name }

        let tlsIdentities: [TLSIdentity] = keyChainIdenitites.map { identity, name in
            TLSIdentity(name: name, identity: identity)
        }

        withAnimation {
            identityNames = pIdentityNames
            identities = tlsIdentities
        }
    }

    var body: some View {
        List {
            ForEach($identities) { $identity in
                NavigationLink {
                    TLSSingleView(identity: $identity)
                } label: {
                    Text(identity.name)
                }
            }
            .onDelete { ids in
                withAnimation {
                    ids.forEach { id in
                        let item = identities[id]

                        do {
                            try Keychain.deleteIdentity(name: item.name)
                        } catch {
                            errorController.push(error: error)
                        }
                        refreshAll()
                    }
                }
            }
        }
        .onAppear {
            refreshAll()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    NavigationLink(destination: {
                        CreateView()
                    }, label: {
                        Label(String(localized: .localizable(.add)), systemImage: "plus")
                    })
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showCreate, content: {
            CreateView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button {
                                showCreate = true
                            } label: {
                                Label(String(localized: .localizable(.add)), systemImage: "plus")
                            }
                            EditButton()
                        }
                    }
                }
        })
    }

    private struct CreateView: View {
        @State private var certificatePassword: String = ""
        @State private var certificateName: String = ""
        @State private var certificateData: Data? = nil

        @State private var isImporting: Bool = false
        @State private var isCertificateValid = false
        @State private var certificateState: CertificateState = .notloaded

        @Environment(\.dismiss) var dismiss
        @EnvironmentObject private var errorController: ErrorController

        private func validateCertificate(certificateData: Data, certificatePassword: String) -> Bool {
            do {
                let _ = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
                return true
            } catch {
                Logger.shared.error("PKCS12 invalid: \(error)")
            }
            return false
        }

        private func saveToKeychain(certificateData: Data, certificatePassword: String, certificateName: String) {
            do {
                let pkc = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
                if let identity = pkc.identity {
                    try Keychain.saveIdentity(identity: identity, name: certificateName)
                }
            } catch {
                errorController.push(error: error)
                Logger.shared.error("Error loading/saving identity to the keychain: \(error)")
            }
        }

        private func validateInput() {
            guard let data = certificateData else {
                isCertificateValid = false
                certificateState = .notloaded
                return
            }
            if validateCertificate(certificateData: data, certificatePassword: certificatePassword) {
                certificateState = .valid
                isCertificateValid = true
            } else {
                certificateState = .wrongPassword
                isCertificateValid = false
            }
        }

        var body: some View {
            Form {
                Section {
                    TextField(String(localized: .localizable(.name)), text: $certificateName)
                    SecureField(String(localized: .login(.password)), text: $certificatePassword).autocorrectionDisabled()
                    Button(String(localized: .settings(.selectCertificate))) {
                        isImporting = true
                    }
                } footer: {
                    switch certificateState {
                    case .notloaded:
                        Text(String(localized: .settings(.certificateNotLoaded)))
                    case .wrongPassword:
                        Text(String(localized: .settings(.certificateLoadError)))
                    case .loadingError:
                        Text(String(localized: .settings(.certificateLoadError)))
                    case .valid:
                        HStack {
                            Image("checkmark.circle.fill")
                        }
                    }
                }

                Section {
                    Button(String(localized: .localizable(.save))) {
                        guard let data = certificateData else {
                            isCertificateValid = false
                            certificateState = .notloaded
                            return
                        }
                        saveToKeychain(certificateData: data, certificatePassword: certificatePassword, certificateName: certificateName)
                        dismiss()
                    }.disabled(!isCertificateValid)
                }
            }
            .onChange(of: certificateData) {
                validateInput()
            }
            .onChange(of: certificatePassword) {
                validateInput()
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pkcs12],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let selectedFile: URL = try result.get().first else { return }
                    if selectedFile.startAccessingSecurityScopedResource() {
                        certificateData = try Data(contentsOf: selectedFile)
                        defer { selectedFile.stopAccessingSecurityScopedResource() }
                        certificateName = selectedFile.lastPathComponent
                    } else {
                        Logger.shared.error("Error opening File from secure context")
                        certificateState = CertificateState.loadingError("Error opening File from secure context")
                    }
                } catch {
                    Logger.shared.error("Error while loding PfX \(error)")
                    certificateState = CertificateState.loadingError(error.localizedDescription)
                }
            }
        }
    }
}

private struct TLSSingleView: View {
    @Binding var identity: TLSIdentity
    @State private var cn: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(LocalizedStringKey(localizable: .name), value: identity.name)
                LabeledContent("CN", value: cn ?? "N/A")
            }
        }
        .onChange(of: identity, initial: true) {
            var optCertificate: SecCertificate?
            SecIdentityCopyCertificate(identity.identity, &optCertificate)

            if let certificate = optCertificate {
                var cn: CFString?
                SecCertificateCopyCommonName(certificate, &cn)

                if cn != nil {
                    self.cn = cn as String?
                }
            }
        }
    }
}
