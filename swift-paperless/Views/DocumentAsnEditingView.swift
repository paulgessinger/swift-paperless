//
//  DocumentAsnEditingView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 02.06.2024.
//

import Foundation
import os
import SwiftUI

struct DocumentAsnEditingView<DocumentType>: View where DocumentType: DocumentProtocol & Equatable {
    @Binding var document: DocumentType
    @Binding var isValid: Bool

    @State private var checking: Bool = false

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    @State private var asn: String = ""
    @State private var changed: Bool = false

    @State private var originalAsn: UInt?

    init(document: Binding<DocumentType>, isValid: Binding<Bool>) {
        _document = document
        _isValid = isValid
        let asn = if let asn = self.document.asn {
            String(asn)
        } else {
            ""
        }
        _asn = State(initialValue: asn)
    }

    private func asnPlusOne() async {
        do {
            let nextAsn = try await store.repository.nextAsn()
            asn = String(nextAsn)
        } catch {
            Logger.shared.error("Error getting next ASN: \(error)")
            errorController.push(error: error)
        }
    }

    private func checkAsn() async -> Bool {
        if !asn.isEmpty, let asn = UInt(asn) {
            do {
                if try await store.repository.document(asn: asn) != nil {
                    // asn already exists, invalid
                    return false
                }
            } catch {
                Logger.shared.error("Got error getting document by ASN for duplication check: \(error)")
                errorController.push(error: error)
            }
        }
        return true
    }

    var body: some View {
        HStack {
            TextField(String(localized: .localizable(.asn)), text: $asn)
                .keyboardType(.numberPad)

            if asn.isEmpty {
                Button(String("+1")) { Task { await asnPlusOne() }}
                    .padding(.vertical, 2)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.accentColor))
                    .foregroundColor(.white)
                    .transition(.opacity)
            }

            if !isValid {
                if checking {
                    ProgressView()
                } else {
                    Label(String(localized: .localizable(.documentDuplicateAsn)), systemImage:
                        "xmark.circle.fill")
                        .foregroundColor(.white)
                        .labelStyle(TightLabel())
                        .padding(.leading, 6)
                        .padding(.trailing, 10)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Color.red)
                        )
                }
            }
        }

        .onChange(of: asn) { [previous = asn, wasValid = isValid] in
            if asn.isEmpty {
                document.asn = nil
                isValid = true
            } else if !asn.isNumber {
                asn = previous
                isValid = wasValid
            } else {
                if let newAsn = UInt(asn) {
                    Task {
                        document.asn = newAsn
                        isValid = false // mark as fals to prevent flickering
                        checking = true
                        isValid = await checkAsn() || document.asn == originalAsn
                        checking = false
                    }
                } else {
                    // Overflow
                    asn = previous
                    isValid = wasValid
                }
            }
        }

        .task {
            originalAsn = document.asn
        }
    }
}
