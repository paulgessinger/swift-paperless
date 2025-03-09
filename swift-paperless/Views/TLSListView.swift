//
//  TLSListView.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import os
import SwiftUI

private enum CertificateState {
    case notloaded
    case wrongPassword
    case valid
    case loadingError(String)
}

struct TLSListView: View {
    @State private var showCreate: Bool = false

    @EnvironmentObject private var errorController: ErrorController

    private var identityManager: IdentityManager

    init(identityManager: IdentityManager) {
        self.identityManager = identityManager
    }

    var body: some View {
        @Bindable var identityManager = identityManager

        List {
            Section {
                ForEach($identityManager.identities) { $identity in
                    NavigationLink {
                        TLSSingleView(identity: $identity)
                    } label: {
                        Text(identity.name)
                    }
                }
                .onDelete { ids in
                    withAnimation {
                        for id in ids {
                            let item = identityManager.identities[id]
                            do {
                                try identityManager.delete(name: item.name)
                            } catch {
                                Logger.shared.error("Error deleting identity: \(error)")
                                errorController.push(error: error)
                            }
                        }
                    }
                }
            } footer: {
                Text(.settings(.identitiesDescription))
            }
        }

        .navigationTitle(.settings(.identities))
        .navigationBarTitleDisplayMode(.inline)

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    NavigationLink(destination: {
                        CreateView(identityManager: identityManager)
                    }, label: {
                        Label(String(localized: .localizable(.add)), systemImage: "plus")
                    })
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showCreate, content: {
            CreateView(identityManager: identityManager)
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

        @Bindable var identityManager: IdentityManager

        private func validateInput() {
            guard let data = certificateData else {
                isCertificateValid = false
                certificateState = .notloaded
                return
            }
            if IdentityManager.validate(certificate: data, password: certificatePassword) {
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
                    SecureField(String(localized: .login(.password)), text: $certificatePassword)
                        .autocorrectionDisabled()

                    Button(String(localized: .settings(.selectCertificate))) {
                        isImporting = true
                    }

                } footer: {
                    switch certificateState {
                    case .notloaded:
                        Text(.settings(.certificateNotLoaded))
                    case .wrongPassword:
                        Text(.settings(.certificateLoadError))
                    case .loadingError:
                        Text(.settings(.certificateLoadError))
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
                        do {
                            try identityManager.save(certificate: data, password: certificatePassword, name: certificateName)
                        } catch {
                            Logger.shared.error("Error saving certificate for identity: \(error)")
                            errorController.push(error: error)
                        }
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

// - MARK: Previews

#Preview {
    @Previewable @State var identityManager = IdentityManager()

    NavigationView {
        TLSListView(identityManager: identityManager)
    }
}
