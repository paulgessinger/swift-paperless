//
//  TLSListView.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import os
import SwiftUI

struct TLSIdentity: Identifiable, Equatable {
    var name: String
    var identity: SecIdentity

    var id: String { name }
}

enum CertificateState {
    case notloaded
    case wrongPassword
    case valid
}

struct TLSListView: View {
    @State var idenities: [TLSIdentity] = []
    @Binding var identityNames: [String]
    @State var showCreate: Bool = false

    func refreshAll() {
        let idenitites: [(SecIdentity, String)] = Keychain.readAllIdenties()

        withAnimation {
            idenities.removeAll()
        }

        identityNames.removeAll()
        idenitites.forEach { ident, name in
            withAnimation {
                identityNames.append(name)
                idenities.append(TLSIdentity(name: name, identity: ident))
            }
        }
    }

    var body: some View {
        List {
            ForEach($idenities) { $identity in
                NavigationLink {
                    TLSSingleView(identity: identity)
                } label: {
                    Text(identity.name)
                }
            }
            .onDelete { ids in
                withAnimation {
                    ids.forEach { id in
                        let item = idenities[id]
                        Keychain.deleteIdentity(name: item.name)
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
                .navigationTitle("T")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button {
                                showCreate = true
                                withAnimation {
                                    // headers.append(.init(key: "Header", value: "Value"))
                                }
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

        private func validateCertificate(certificateData: Data, certificatePassword: String) -> Bool {
            do {
                let _ = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
                return true
            } catch {}
            return false
        }

        private func saveToKeychain(certificateData: Data, certificatePassword: String, certificateName: String) {
            do {
                let pkc = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
                if let identity = pkc.identity {
                    Keychain.saveIdentity(identity: identity, name: certificateName)
                }
            } catch {
                print(error)
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
                    }
                } catch {
                    Logger.shared.error("erro while loding PfX \(error)")
                }
            }
        }
    }
}

struct TLSSingleView: View {
    @State var identity: TLSIdentity
    @State var cn: String?

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
