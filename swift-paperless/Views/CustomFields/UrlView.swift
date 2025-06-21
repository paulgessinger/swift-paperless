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

    private func valid(urlString: String) -> (URL?, Bool) {
        guard urlString.count > 0 else {
            return (nil, true)
        }
        guard let u = URL(string: urlString), u.scheme != nil, u.host != nil else {
            return (nil, false)
        }
        return (u, true)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(instance.field.name)
                .font(.footnote)
                .bold()
            HStack {
                TextField(instance.field.name, text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                let (url, isValid) = valid(urlString: url)
                if self.url.count > 0 {
                    HStack {
                        Text(isValid ? .customFields(.urlFieldOpenLabel) : .customFields(.urlFieldInvalidLabel))
                        Image(systemName: isValid ? "arrow.up.right.circle.fill" : "xmark.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .foregroundStyle(isValid ? Color.accentColor : Color.red)
                    .if(isValid) { view in
                        view.onTapGesture {
                            if let url {
                                openURL(url)
                            }
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

        Text("VALID: \(instance.value.isValid ? "YES" : "NO")")
    }
}
