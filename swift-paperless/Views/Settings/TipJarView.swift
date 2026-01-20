import StoreKit
import SwiftUI

@Observable
@MainActor
class TipJarStore {
  enum LoadState {
    case idle
    case loading
    case loaded([ProductID: Product])
    case failed
  }

  struct TipJarAlert: Identifiable {
    let id = UUID()
    let title: LocalizedStringResource
    let message: LocalizedStringResource
  }

  enum ProductID: String, CaseIterable {
    case tip_small, tip_medium, tip_large, tip_xlarge

    var emoji: String {
      switch self {
      case .tip_small: "☕"
      case .tip_medium: "🙌"
      case .tip_large: "🤩"
      case .tip_xlarge: "💰"
      }
    }
  }

  private(set) var loadState: LoadState = .idle
  var purchasingProductID: String? = nil
  var alert: TipJarAlert? = nil

  @ObservationIgnored
  private var updatesTask: Task<Void, Never>?

  init() {
    updatesTask = Task { await listenForTransactions() }
  }

  deinit {
    updatesTask?.cancel()
  }

  func loadProducts() async {
    loadState = .loading
    do {
      let raw = try await Product.products(for: ProductID.allCases.map { $0.rawValue })
      var products = [ProductID: Product]()
      for product in raw {
        guard let id = ProductID(rawValue: product.id) else { continue }
        products[id] = product
      }
      loadState = .loaded(products)
    } catch {
      loadState = .failed
    }
  }

  func purchase(_ product: Product) async {
    purchasingProductID = product.id
    defer { purchasingProductID = nil }

    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verificationResult):
        let transaction = try checkVerified(verificationResult)
        await transaction.finish()
        Haptics.shared.notification(.success)
        alert = TipJarAlert(
          title: .settings(.tipJarThanksTitle),
          message: .settings(.tipJarThanksMessage))
      case .pending:
        alert = TipJarAlert(
          title: .settings(.tipJarPendingTitle),
          message: .settings(.tipJarPendingMessage))
      case .userCancelled:
        break
      @unknown default:
        break
      }
    } catch {
      alert = TipJarAlert(
        title: .settings(.tipJarPurchaseErrorTitle),
        message: .settings(.tipJarPurchaseErrorMessage))
    }
  }

  private func listenForTransactions() async {
    for await result in Transaction.updates {
      guard let transaction = try? checkVerified(result) else { continue }
      await transaction.finish()
    }
  }

  private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let safe):
      return safe
    case .unverified:
      throw TipJarStoreError.failedVerification
    }
  }
}

enum TipJarStoreError: Error {
  case failedVerification
}

struct TipJarView: View {
  @State private var store = TipJarStore()

  var body: some View {
    Form {
      Section {
        VStack {
          HStack {
            Text("🫙")
              .font(.custom("big", size: 50, relativeTo: .title))
            Text(.settings(.tipJarTipsLabel))
              .font(.title)
              .foregroundStyle(.accent)
              .bold()
          }
          Text(.settings(.tipJarDescription))
            .font(.callout)
        }
      }

      Section(String(localized: .settings(.tipJarOptionsTitle))) {
        tipOptions
      }
    }
    .navigationTitle(Text(.settings(.tipJarTitle)))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await store.loadProducts()
    }
    .refreshable {
      await store.loadProducts()
    }

    .alert(
      unwrapping: $store.alert,
      title: { alert in
        Text(alert.title)
      },
      actions: { alert in
        Button(.localizable(.ok)) { store.alert = nil }
      },
      message: { alert in
        Text(alert.message)
      })

    //    .alert(item: $store.alert) { alert in
    //      Alert(
    //        title: Text(alert.title),
    //        message: Text(alert.message),
    //        dismissButton: .default(Text(.localizable(.ok))))
    //    }
  }

  @ViewBuilder
  private var tipOptions: some View {
    switch store.loadState {
    case .idle, .loading:
      HStack {
        ProgressView(String(localized: .settings(.tipJarLoading)))
          .frame(maxWidth: .infinity, alignment: .center)
      }
    case .failed:
      Text(.settings(.tipJarLoadError))
        .foregroundStyle(.secondary)
    case .loaded(let products):
      if products.isEmpty {
        Text(.settings(.tipJarNoProducts))
          .foregroundStyle(.secondary)
      } else {
        let knownProducts = TipJarStore.ProductID.allCases.compactMap { id in
          products[id].map { (id, $0) }
        }
        ForEach(knownProducts, id: \.0) { id, product in
          tipRow(for: product, id: id)
        }
      }
    }
  }

  private func tipRow(for product: Product, id: TipJarStore.ProductID) -> some View {
    let isProcessing = store.purchasingProductID == product.id

    return Button {
      Task { await store.purchase(product) }
    } label: {
      HStack(alignment: .center, spacing: 12) {
        Text(id.emoji)
          .font(.title)
        VStack(alignment: .leading, spacing: 4) {
          Text(product.displayName)
          if !product.description.isEmpty {
            Text(product.description)
              .font(.footnote)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        //        Spacer()

        VStack {
          if isProcessing {
            ProgressView()
          } else {
            Text(product.displayPrice)
          }
        }
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 5)
        .background(Capsule())
      }
      .animation(.default, value: store.purchasingProductID)
    }
    .disabled(store.purchasingProductID != nil)
  }
}

#Preview("TipJarView") {
  NavigationStack {
    TipJarView()
  }
}
