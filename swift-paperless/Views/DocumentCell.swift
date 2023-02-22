//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

struct DocumentCell: View {
    @EnvironmentObject var store: DocumentStore

    let document: Document

    @State private var correspondent: Correspondent?
    @State private var documentType: DocumentType?

    var body: some View {
        HStack(alignment: .top) {
            AuthAsyncImage(url: URL(string: "\(API_BASE_URL)documents/\(document.id)/thumb/")) {
                image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150, alignment: .top)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
            } placeholder: {
                Rectangle().fill(.gray).scaledToFit().overlay(ProgressView())
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading) {
                Group {
                    Text.titleCorrespondent(value: correspondent)
                        + Text("\(document.title)")
                }.task {
                    if let cId = document.correspondent {
                        correspondent = await store.getCorrespondent(id: cId)
                    }

                    if let dId = document.documentType {
                        documentType = await store.getDocumentType(id: dId)
                    }
                }

                Text.titleDocumentType(value: documentType)
                    .foregroundColor(Color.orange)

                Text(document.created, style: .date)
            }
        }
    }
}
