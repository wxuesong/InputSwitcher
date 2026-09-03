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
        activity = .loading
        if product == nil {
            await loadProduct()
        }
        await refreshEntitlements()
        if product != nil || isPro {
            activity = .idle
        } else {
            activity = .failed
        }
    }

    func purchasePro() async {
        activity = .purchasing

        if product == nil {
            await loadProduct()
        }

        guard let product else {
            activity = .failed
            return
        }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    activity = .failed
                    return
                }
                // 关键修复：先标记购买成功再finish，确保UI立即更新
                hasProEntitlement = true
                await transaction.finish()
                // 后台刷新保证同步
                Task { await refreshEntitlements() }
                activity = .idle
                NotificationCenter.default.post(name: .proEntitlementDidChange, object: nil)
            case .pending:
                activity = .pending
            case .userCancelled:
                activity = .idle
            @unknown default:
                activity = .failed
            }
        } catch {
            // 购买失败，保持 failed 状态
            activity = .failed
        }
    }

    func restorePurchases() async {
        activity = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            activity = .idle
        } catch {
            activity = .failed
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
}