//
//  MonetaryView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 19.06.25.
//

import DataModel
import SwiftUI

struct MonetaryView: View {
  @Binding var instance: CustomFieldInstance

  @State private var amount: Decimal? = nil
  @State private var amountString: String = ""

  @State private var currency: String = ""

  @Environment(\.locale) private var locale
  @Environment(\.colorScheme) private var colorScheme

  init(instance: Binding<CustomFieldInstance>) {
    _instance = instance
  }

  private var defaultCurrency: String {
    instance.field.extraData.defaultCurrency ?? Locale.current.currency?.identifier ?? ""
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text(instance.field.name)
        .font(.footnote)
        .bold()

      HStack {
        if case .monetary(let currency, let amount) = instance.value {
          Text(amount ?? 0.00, format: .currency(code: currency))
            .padding(.vertical, 4)
            .padding(.horizontal)
            .background(
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.pickerBackground)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.default, value: instance.value)
            .contentTransition(.numericText())
        }

        TextField(defaultCurrency, text: $currency)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .fixedSize()

        TextField(.customFields(.monetaryAmountPlaceholder), text: $amountString)
          .keyboardType(.decimalPad)
      }
    }
    .onChange(of: amountString) { old, new in
      guard amountString.count > 0 else {
        amount = nil
        instance.value = .monetary(currency: currency, amount: nil)
        return
      }

      // @FIXME: This lets through characters in the string, not sure if this is a problem
      guard let val = Decimal(string: new, locale: locale) else {
        amountString = old  // Revert to old value if invalid
        return
      }

      amount = val
      instance.value = .monetary(currency: currency, amount: val)
    }

    .onChange(of: currency) { old, new in

      // check if is valid currency code
      let ex = /^[A-Z]*$/
      if new.wholeMatch(of: ex) == nil {
        currency = old  // Revert to old value if invalid
        return
      }

      currency = new

      var setCurrency = new
      if setCurrency.isEmpty {
        setCurrency = defaultCurrency
      }

      if new.count == 0 || new.count == 3 {
        instance.value = .monetary(currency: setCurrency, amount: amount)
      }
    }

    .task {
      if case .monetary(let currency, let amount) = instance.value {
        self.amount = amount
        amountString =
          amount.map {
            $0.formatted(
              .number.locale(
                locale
              )
              .grouping(.never)
              .decimalSeparator(strategy: .always)
              .precision(.fractionLength(2)))
          } ?? ""
        self.currency = currency
      }
    }
  }
}

private let field = CustomField(id: 1, name: "Custom monetary", dataType: .monetary)

#Preview {
  @Previewable @State var instance = CustomFieldInstance(
    field: field, value: .monetary(currency: "EUR", amount: 1234.56))
  @Previewable @State var instance2 = CustomFieldInstance(
    field: field, value: .monetary(currency: "EUR", amount: nil))

  return Form {
    MonetaryView(instance: $instance)
    MonetaryView(instance: $instance2)

    Section("Instance") {
      Text(String(describing: instance))
    }
    Section("Instance 2") {
      Text(String(describing: instance2))
    }
  }
}
