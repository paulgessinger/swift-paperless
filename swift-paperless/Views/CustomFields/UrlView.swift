//
//  UrlView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.06.25.
//

import Common
import DataModel
import SwiftUI

struct UrlView: View {
    @Binding var instance: CustomFieldInstance

    @State private var url: String = ""

    @Environment(\.openURL) private var openURL

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .url(u) = instance.wrappedValue.value {
            _url = State(initialValue: u?.absoluteString ?? "")
        }
    }

    private func valid(urlString: String) -> URL? {
        guard let u = URL(string: urlString), u.scheme != nil, u.host != nil else {
            return nil
        }
        return u
    }

    var body: some View {
        Section(instance.field.name) {
            HStack {
                TextField(instance.field.name, text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                let validUrl = valid(urlString: url)
                let isValid = validUrl != nil
                HStack {
                    Text(isValid ? .customFields(.urlFieldOpenLabel) : .customFields(.urlFieldInvalidLabel))
                    Image(systemName: isValid ? "arrow.up.right.circle.fill" : "xmark.circle.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(isValid ? Color.accentColor : Color.red)
                .if(isValid) { view in
                    view.onTapGesture {
                        if let validUrl {
                            openURL(validUrl)
                        }
                    }
                }
            }
        }
        .animation(.spring, value: url)

        .onChange(of: url) { _, new in
            guard !new.isEmpty else {
                instance.value = .url(nil)
                return
            }

            guard let url = URL(string: new) else {
                return
            }

            instance.value = .url(url)
        }
    }
}

private let field = CustomField(id: 1, name: "Custom url", dataType: .url)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(field: field, value: .url(#URL("https://example.com")))

    return Form {
        UrlView(instance: $instance)

        Section("Instance") {
            Text(String(describing: instance))
        }
    }
}
