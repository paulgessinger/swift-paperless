//
//  UrlEntryView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import AppShared
import AppViews
import SwiftUI
import UIKit

private typealias Scheme = LoginViewModel.Scheme

struct UrlEntryView: View {
  @Binding var focus: Bool
  var onSubmit: () -> Void

  @Environment(LoginViewModel.self) private var viewModel

  var body: some View {
    @Bindable var viewModel = viewModel

    HStack(spacing: 1) {
      HStack(spacing: 3) {
        Label(
          localized: .login(.schemeSelectionLabel),
          systemImage: "chevron.up.chevron.down"
        )
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
        } label: {
          Color.clear
        }
      }
      .tint(.primary)

      SchemeSplittingTextField(
        text: $viewModel.url,
        isFocused: $focus,
        placeholder: String(localized: .login(.urlPlaceholder)),
        onScheme: { viewModel.scheme = $0 },
        onSubmit: onSubmit
      )
      .padding(.vertical, 10)
      Spacer()
      switch viewModel.loginState {
      case .checking:
        ProgressView()
      case .valid:
        Label(
          localized: .login(.urlValid),
          systemImage:
            "checkmark.circle.fill"
        )
        .labelStyle(.iconOnly)
        .foregroundStyle(Color.accentColor)
      case .error:
        Label(
          localized: .login(.urlError),
          systemImage:
            "xmark.circle.fill"
        )
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

/// Address field that moves a typed or pasted `http://` / `https://` into the
/// scheme picker as part of the keystroke itself. A SwiftUI `TextField`
/// rewritten from `onChange` loses the keystroke that follows the rewrite.
private struct SchemeSplittingTextField: UIViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  var placeholder: String
  var onScheme: (Scheme) -> Void
  var onSubmit: () -> Void

  func makeUIView(context: Context) -> UITextField {
    let field = UITextField()
    field.placeholder = placeholder
    field.font = .preferredFont(forTextStyle: .body)
    field.adjustsFontForContentSizeCategory = true
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.spellCheckingType = .no
    field.keyboardType = .URL
    field.returnKeyType = .continue
    field.delegate = context.coordinator
    field.addTarget(
      context.coordinator, action: #selector(Coordinator.editingChanged(_:)),
      for: .editingChanged)
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }

  func updateUIView(_ field: UITextField, context: Context) {
    context.coordinator.parent = self
    if field.text != text {
      field.text = text
    }
    if isFocused, !field.isFirstResponder {
      DispatchQueue.main.async { field.becomeFirstResponder() }
    } else if !isFocused, field.isFirstResponder {
      DispatchQueue.main.async { field.resignFirstResponder() }
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context)
    -> CGSize?
  {
    CGSize(width: proposal.width ?? 200, height: uiView.intrinsicContentSize.height)
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: SchemeSplittingTextField

    init(parent: SchemeSplittingTextField) {
      self.parent = parent
    }

    func textField(
      _ field: UITextField, shouldChangeCharactersIn range: NSRange,
      replacementString string: String
    ) -> Bool {
      let current = field.text ?? ""
      guard let swiftRange = Range(range, in: current) else { return true }
      let updated = current.replacingCharacters(in: swiftRange, with: string)

      guard let match = updated.wholeMatch(of: /(?s)(https?):\/\/(.*)/),
        let scheme = Scheme(rawValue: String(match.1))
      else {
        return true
      }

      let rest = String(match.2)
      field.text = rest
      let end = field.endOfDocument
      field.selectedTextRange = field.textRange(from: end, to: end)
      parent.text = rest
      parent.onScheme(scheme)
      return false
    }

    @objc func editingChanged(_ field: UITextField) {
      parent.text = field.text ?? ""
    }

    func textFieldDidBeginEditing(_ field: UITextField) {
      if !parent.isFocused { parent.isFocused = true }
    }

    func textFieldDidEndEditing(_ field: UITextField) {
      if parent.isFocused { parent.isFocused = false }
    }

    func textFieldShouldReturn(_ field: UITextField) -> Bool {
      parent.onSubmit()
      return false
    }
  }
}
