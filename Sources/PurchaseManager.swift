import Combine
import Foundation
import StoreKit

extension Notification.Name {
    static let proEntitlementDidChange = Notification.Name("InputSwitcher.proEntitlementDidChange")
}

enum PurchaseActivity: Equatable {
    case idle
    case loading
    case purchasing
    case restoring
    case pending
    case failed
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    static let proProductID = "com.hans.InputSwitcher.pro"
    static let freeRuleLimit = 5
    static let freeLockedRuleLimit = 1
#if DEBUG
    private static let testUnlockKey = "testUnlockEnabled"
#endif

    @Published private(set) var product: Product?
    @Published private(set) var hasProEntitlement = false
#if DEBUG
    @Published var testUnlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(testUnlockEnabled, forKey: Self.testUnlockKey)
            NotificationCenter.default.post(name: .proEntitlementDidChange, object: nil)
        }
    }
#endif
    @Published private(set) var activity: PurchaseActivity = .loading

    var isPro: Bool {
#if DEBUG
        hasProEntitlement || testUnlockEnabled
#else
        hasProEntitlement
#endif
    }

    private var transactionUpdates: Task<Void, Never>?
    private var productLoadingTask: Task<Product?, Never>?
    private var activityGeneration = 0

    var displayPrice: String {
        product?.displayPrice ?? L10n.string("pro.price_unavailable")
    }

    private init() {
#if DEBUG
        testUnlockEnabled = UserDefaults.standard.bool(forKey: Self.testUnlockKey)
#endif
        transactionUpdates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }

        Task { [weak self] in await self?.refresh() }
    }

    deinit {
        transactionUpdates?.cancel()
        productLoadingTask?.cancel()
    }

    func refresh() async {
        let operation = beginActivity(.loading)
        if product == nil {
            await loadProduct()
        }
        await refreshEntitlements()
        if operation == activityGeneration {
            activity = product != nil || isPro ? .idle : .failed
        }
    }

    func purchasePro() async {
        let operation = beginActivity(.purchasing)

        if product == nil {
            await loadProduct()
        }

        guard let product else {
            finishActivity(.failed, operation: operation)
            return
        }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    finishActivity(.failed, operation: operation)
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                finishActivity(.idle, operation: operation)
            case .pending:
                finishActivity(.pending, operation: operation)
            case .userCancelled:
                finishActivity(.idle, operation: operation)
            @unknown default:
                finishActivity(.failed, operation: operation)
            }
        } catch {
            finishActivity(.failed, operation: operation)
        }
    }

    func restorePurchases() async {
        let operation = beginActivity(.restoring)
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            finishActivity(.idle, operation: operation)
        } catch {
            finishActivity(.failed, operation: operation)
        }
    }

    private func loadProduct() async {
        if let productLoadingTask {
            product = await productLoadingTask.value
            return
        }

        let task = Task<Product?, Never> {
            do {
                let products = try await Product.products(for: [Self.proProductID])
                return products.first { $0.id == Self.proProductID }
            } catch {
                return nil
            }
        }
        productLoadingTask = task
        product = await task.value
        productLoadingTask = nil
    }

    private func refreshEntitlements() async {
        var hasProEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.proProductID,
                  transaction.revocationDate == nil else {
                continue
            }
            hasProEntitlement = true
            break
        }

        let wasPro = isPro
        self.hasProEntitlement = hasProEntitlement
        if wasPro != isPro {
            NotificationCenter.default.post(name: .proEntitlementDidChange, object: nil)
        }
    }

    private func beginActivity(_ activity: PurchaseActivity) -> Int {
        activityGeneration += 1
        self.activity = activity
        return activityGeneration
    }

    private func finishActivity(_ activity: PurchaseActivity, operation: Int) {
        guard operation == activityGeneration else { return }
        self.activity = activity
    }
}
