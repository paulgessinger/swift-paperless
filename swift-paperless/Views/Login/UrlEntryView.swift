//
//  UrlEntryView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import SwiftUI

private typealias Scheme = LoginViewModel.Scheme

struct UrlEntryView: View {
    @FocusState.Binding var focus: Bool

    @Environment(LoginViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        HStack(spacing: 1) {
            HStack(spacing: 3) {
                Label(localized: .login(.schemeSelectionLabel),
                      systemImage: "chevron.up.chevron.down")
                    .labelStyle(.iconOnly)
                    .font(.footnote)

                VStack {
                    if viewModel.scheme == .http {
                        Text(Scheme.http.label)
                            .transition(
                                .move(edge: .bottom)
                                    .combined(with: .opacity)
                            )
                    }
                    if viewModel.scheme == .https {
                        Text(Scheme.https.label)
                            .transition(
                                .move(edge: .top)
                                    .combined(with: .opacity)
                            )
                    }
                }
                .fontWeight(.medium)
                .animation(.spring(duration: 0.2, bounce: 0.5), value: viewModel.scheme)
            }
            .overlay {
                Menu {
                    ForEach([Scheme.https, Scheme.http], id: \.self) { value in
                        Button {
                            viewModel.scheme = value
                        } label: {
                            if viewModel.scheme == value {
                                Label(value.label, systemImage: "checkmark")
                            } else {
                                Text(value.label)
                            }
                        }
                        .disabled(viewModel.scheme == value)
                    }
                } label: { Color.clear }
            }
            .tint(.primary)

            TextField(String(localized: .login(.urlPlaceholder)), text: $viewModel.url)
                .padding(.vertical, 10)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focus)
                .submitLabel(.next)
            Spacer()
            switch viewModel.loginState {
            case .checking:
                ProgressView()
            case .valid:
                Label(localized: .login(.urlValid), systemImage:
                    "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.accentColor)
            case .error:
                Label(localized: .login(.urlError), systemImage:
                    "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            case .empty:
                EmptyView()
            }
        }
        .animation(.spring(duration: 0.2), value: viewModel.loginState)
        .animation(.spring(duration: 0.2), value: viewModel.scheme)
    }
}
