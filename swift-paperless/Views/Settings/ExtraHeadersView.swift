//
//  ExtraHeadersView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 07.05.23.
//

import Networking
import SwiftUI
import os

struct ExtraHeadersView: View {
  @Binding var headers: [Connection.HeaderValue]

  private struct SingleView: View {
    @Binding var header: Connection.HeaderValue

    var body: some View {
      Form {
        Section {
          TextField(String(localized: .login(.extraHeadersKey)), text: $header.key)
            .clearable($header.key)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .onChange(of: header.key) { _, value in
              header.key = value.replacingOccurrences(of: " ", with: "")
            }
        } header: {
          Text(.login(.extraHeadersKey))
        } footer: {
          if header.key == "Authorization" {
            Text(.login(.extraHeaderAuthorization))
          }
        }

        Section(String(localized: .login(.extraHeadersValue))) {
          TextField(String(localized: .login(.extraHeadersValue)), text: $header.value)
            .clearable($header.value)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
        }
      }
    }
  }

  var body: some View {
    List {
      Section {
        ForEach($headers, id: \.id) { $header in
          NavigationLink {
            SingleView(header: $header)
          } label: {
            LabeledContent(header.key, value: header.value)
          }
        }
        .onDelete { ids in
          withAnimation {
            headers.remove(atOffsets: ids)
          }
        }
      } footer: {
        Text(.login(.extraHeadersDescription))
      }
    }

    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        HStack {
          Button {
            withAnimation {
              headers.append(.init(key: "Header", value: "Value"))
            }
          } label: {
            Label(String(localized: .localizable(.add)), systemImage: "plus")
          }
          EditButton()
        }
      }
    }

    .navigationTitle(Text(.login(.extraHeaders)))
  }
}
