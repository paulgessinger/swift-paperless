//
//  TLSListView.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import SwiftUI

struct TLSIdentity: Identifiable, Equatable {
    var name: String
    //var identity: SecIdentity
    
    var id: String { name }
}

enum CertificateState {
    case notloaded
    case wrongPassword
    case valid
}

struct TLSListView: View {
    @State var idenities: [TLSIdentity] = []
    
    @State var showCreate: Bool = false
    
    
    func refreshAll() {
        print("Refresh")
        let idenitites: [(SecIdentity, String)] = Keychain.readAllIdenties()
        
        withAnimation{
            self.idenities.removeAll()
        }
        
        idenitites.forEach{ ident, name in
            print(name)
            withAnimation{
                self.idenities.append(TLSIdentity(name: name))
            }
        }
    }
    
    var body: some View {
        List {
            ForEach($idenities){ $identity in
                Text(identity.name)
            }
            .onDelete { ids in
                withAnimation {
                    ids.forEach{ id in
                        let item = idenities[id]
                        print("Delete \(item.name)")
                        Keychain.deleteIdentity(name: item.name)
                        refreshAll()
                    }
                }
            }
        }
        .onAppear{
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
                .toolbar(){
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button {
                                showCreate = true
                                withAnimation {
                                    //headers.append(.init(key: "Header", value: "Value"))
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
        
        
        
        private func validateCertificate(certificateData: Data, certificatePassword: String) -> Bool {
            do {
                let _ = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
                return true
            } catch {
                
            }
            return false
        }
        
        private func saveToKeychain(certificateData: Data, certificatePassword: String, certificateName: String){
            do {
                let pkc = try PKCS12(pkcs12Data: certificateData, password: certificatePassword)
                if let identity = pkc.identity {
                    Keychain.saveIdentity(identity: identity, name: certificateName)
                }
            }catch {
                print(error)
            }
        }
        
        private func validateInput(){
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
        
        var body: some View {
            Form {
                Section {
                    TextField("Certificate Name", text: $certificateName)
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
                        saveToKeychain(certificateData: data, certificatePassword: certificatePassword, certificateName: certificateName)
                    }.disabled(!isCertificateValid)
                    
                }
            }
            .onChange(of: certificateData){
                validateInput()
            }
            .onChange(of: certificatePassword){
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
}
