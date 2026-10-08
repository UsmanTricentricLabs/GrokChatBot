import Foundation
import StoreKit
internal import Combine

enum PremiumProductId: String, CaseIterable {
    
    case weekly = "com.gemx.weekly"
    case monthly = "com.gemx.monthly"
    case yearly = "com.gemx.yearly"
    
    static var allIds: Set<String> {
        Set(PremiumProductId.allCases.map { $0.rawValue })
    }
}

@MainActor
class IAPManager: ObservableObject {
    
    @Published var isPremiumUnlocked: Bool = false
    @Published var showPremiumOnLaunch: Bool = false
    @Published var isVerifying: Bool = true
    @Published var products: [PremiumProductId: Product] = [:]
    @Published var priceStrings: [PremiumProductId: String] = [:]
    @Published var purchaseInProgress: Bool = false
    @Published var errorMessage: String? = nil

    /// Whether the App Store will actually honour the product's introductory offer for this
    /// account. A product can carry a trial the customer has already used, so the paywall
    /// asks this before it promises anything.
    @Published var introEligibility: [PremiumProductId: Bool] = [:]

    static let shared = IAPManager()
    
    private let premiumKey = "isPremium"
    private var updateListenerTask: Task<Void, Never>? = nil
    
    init() {
        isPremiumUnlocked = UserDefaults.standard.bool(forKey: premiumKey)
        fetchProducts()
        verifySubscriptions()
        listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func isPurchased() -> Bool {
        return UserDefaults.standard.bool(forKey: self.premiumKey)
    }
    
    /// Fetch all subscription products (StoreKit 2)
    
    func fetchProducts() {
        Task {
            do {
                let storeProducts = try await Product.products(for: Array(PremiumProductId.allIds))  //StoreKit 2 API that fetches products you’ve defined in App Store Connect.
                var newProducts: [PremiumProductId: Product] = [:]
                var newPriceStrings: [PremiumProductId: String] = [:]
                
                for product in storeProducts {
                    if let premiumId = PremiumProductId(rawValue: product.id) {
                        newProducts[premiumId] = product
                        newPriceStrings[premiumId] = product.displayPrice
                        
                        var trialInfo = "No trial available"
                        if let subscription = product.subscription {
                            if let intro = subscription.introductoryOffer {
                                // Example: "3 Days Free Trial"
                                trialInfo = "\(intro.period.value) \(intro.period.unit) Free Trial"
                            }
                        }
                        
                        print("""
                        ------------------------
                        Product ID: \(product.id)
                        Title: \(product.displayName)
                        Description: \(product.description)
                        Price: \(product.displayPrice)
                        Trial Info: \(trialInfo)
                        ------------------------
                        """)
                    }
                }
                
                self.products = newProducts
                self.priceStrings = newPriceStrings
                await self.refreshIntroEligibility(for: newProducts)
            } catch {
                print("⚠️ Error fetching products: \(error.localizedDescription)")
            }
        }
    }
    
    /// Purchase a subscription (StoreKit 2)
    
    
    func purchase(_ productId: PremiumProductId) {
        guard let product = products[productId] else {
            errorMessage = "iap.productNotLoaded".localized
            return
        }
        
        // ✅ FIX: Check if already purchased before attempting purchase
        Task {
            // Check current entitlements first
            for await verificationResult in Transaction.currentEntitlements {
                if case .verified(let transaction) = verificationResult {
                    if PremiumProductId(rawValue: transaction.productID) != nil {
                        await MainActor.run {
                            self.isPremiumUnlocked = true
                            UserDefaults.standard.set(true, forKey: self.premiumKey)
                            self.showPremiumOnLaunch = false
                        }
                        print("✅ Already has active subscription — skipping purchase")
                        return  // Exit early, no need to show purchase sheet
                    }
                }
            }
            
            // ✅ No active subscription found — proceed with purchase
            await MainActor.run {
                self.purchaseInProgress = true
            }
            
            self.errorMessage = nil
            
            do {
                print("🛒 Starting purchase for \(product.id)...")
                
                let result = try await product.purchase()
                
                await MainActor.run {
                    self.purchaseInProgress = false
                }
                
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        print("✅ Purchased: \(transaction.productID)")
                        await transaction.finish()
                        await MainActor.run {
                            self.isPremiumUnlocked = true
                            UserDefaults.standard.set(self.isPremiumUnlocked, forKey: self.premiumKey)
                            self.showPremiumOnLaunch = false
                        }
                        
                    case .unverified(_, let error):
                        print("⚠️ Transaction unverified: \(error.localizedDescription)")
                        await MainActor.run {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                    
                case .userCancelled:
                    print("🚫 Purchase cancelled by user")
                    
                case .pending:
                    print("⏳ Purchase pending...")
                    
                @unknown default:
                    print("Unknown purchase result")
                }
                
            } catch {
                await MainActor.run {
                    self.purchaseInProgress = false
                    self.errorMessage = error.localizedDescription
                }
                print("❌ Purchase failed: \(error.localizedDescription)")
            }
        }
    }
    
    
    /// Restore subscriptions (StoreKit 2)
    ///
    /// `onAlreadyPurchased` fires only when a subscription was found, so existing callers keep
    /// their behaviour. `onFinished` reports the outcome to callers that also need to react to
    /// "nothing to restore", such as the paywall.
    
    func restorePurchases(onAlreadyPurchased: (() -> Void)? = nil,
                          onFinished: ((Bool) -> Void)? = nil) {
        Task {
            
            // ✅ Step 1: Check current entitlements first (no prompt)
            if await hasActiveEntitlement() {
                await MainActor.run {
                    self.isPremiumUnlocked = true
                    UserDefaults.standard.set(true, forKey: self.premiumKey)
                    self.showPremiumOnLaunch = false
                    onAlreadyPurchased?()
                    onFinished?(true)
                }
                print("✅ Already purchased — restored silently")
                return
            }
            
            // ✅ Step 2: Show loading indicator
            await MainActor.run {
                self.purchaseInProgress = true
            }
            
            do {
                // ✅ Step 3: Sync with App Store
                try await AppStore.sync()
                print("🔄 Restore triggered successfully")
                
                // ✅ Step 4: Sandbox can deliver the restored transaction a moment after the
                // sync returns, so entitlements are re-read for a few seconds before giving up.
                // Polling rather than reading `Transaction.updates` here: the app already keeps
                // a permanent listener on that stream, and a second reader would wait forever
                // on an account that has nothing to restore.
                var restored = false
                
                for _ in 0..<10 {
                    if await hasActiveEntitlement() {
                        restored = true
                        break
                    }
                    
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                
                await MainActor.run {
                    self.purchaseInProgress = false
                    
                    if restored {
                        self.isPremiumUnlocked = true
                        UserDefaults.standard.set(true, forKey: self.premiumKey)
                        self.showPremiumOnLaunch = false
                        onAlreadyPurchased?()
                        print("🎉 Restored — premium unlocked")
                    } else {
                        print("🔒 No subscription found — user may not have purchased")
                    }
                    
                    onFinished?(restored)
                }
                
            } catch {
                await MainActor.run {
                    self.purchaseInProgress = false
                    self.errorMessage = error.localizedDescription
                    onFinished?(false)
                }
                print("❌ Restore failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// True when the App Store currently entitles this account to one of the premium products.
    private func hasActiveEntitlement() async -> Bool {
        var found = false
        
        for await verificationResult in Transaction.currentEntitlements {
            if case .verified(let transaction) = verificationResult {
                if PremiumProductId(rawValue: transaction.productID) != nil {
                    found = true
                    await transaction.finish()
                }
            }
        }
        
        return found
    }
    
    /// Verify active subscription (StoreKit 2)
    func verifySubscriptions() {
        Task {
            isVerifying = true
            print("🟡 [Subscription] Starting verification process...")
            
            var hasActiveSubscription = false
            
            do {
                for await verificationResult in Transaction.currentEntitlements {
                    switch verificationResult {
                    case .verified(let transaction):
                        print("✅ [Verified Transaction]")
                        print("   • Product ID: \(transaction.productID)")
                        print("   • Purchase Date: \(transaction.purchaseDate)")
                        print("   • Expiration Date: \(String(describing: transaction.expirationDate))")
                        
                        if let premiumProduct = PremiumProductId(rawValue: transaction.productID) {
                            print("   → Matched Premium Product: \(premiumProduct)")
                            hasActiveSubscription = true
                        } else {
                            print("   → Not a Premium Product")
                        }
                        
                    case .unverified(let transaction, let error):
                        print("❌ [Unverified Transaction]")
                        print("   • Product ID: \(transaction.productID)")
                        print("   • Error: \(error.localizedDescription)")
                    }
                }
                
                isPremiumUnlocked = hasActiveSubscription
                UserDefaults.standard.set(isPremiumUnlocked, forKey: premiumKey)
                //  Drives the paywall shown at launch. Entitlements decide it, never a
                //  stored flag, so a lapsed subscription brings the paywall back.
                showPremiumOnLaunch = !hasActiveSubscription
                print(hasActiveSubscription
                      ? "🎉 [Subscription] Premium access UNLOCKED"
                      : "🔒 [Subscription] No active premium subscription found.")
                
            } catch {
                print("🚫 [Subscription] Receipt verification failed: \(error.localizedDescription)")
            }
            
            isVerifying = false
            print("🟢 [Subscription] Verification process completed.\n")
        }
    }
    
    
    /// Listen for live transaction updates
    private func listenForTransactions() {
        updateListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                switch result {
                case .verified(let transaction):
                    if PremiumProductId(rawValue: transaction.productID) != nil {
                        await transaction.finish()
                        await MainActor.run {
                            self.isPremiumUnlocked = true
                            UserDefaults.standard.set(self.isPremiumUnlocked, forKey: self.premiumKey)
                            self.showPremiumOnLaunch = false
                        }
                    }
                case .unverified(_, _):
                    break
                }
            }
        }
    }
}


// MARK: - Paywall Presentation
//
//  Everything the paywall shows about a plan is read back from the StoreKit product here:
//  price, billing period and introductory offer. Nothing is written into the UI by
//  hand, so a price or trial changed in App Store Connect changes the paywall on its own.

extension IAPManager {

    /// Plans in the order the paywall lists them.
    static let planOrder: [PremiumProductId] = [.weekly, .monthly, .yearly]

    func product(for id: PremiumProductId) -> Product? {
        products[id]
    }

    /// The App Store's localised price for the plan, or nil while products are still loading.
    func displayPrice(for id: PremiumProductId) -> String? {
        products[id]?.displayPrice
    }

    /// "Per week" / "Per month" / "Per year", taken from the product's billing period.
    func billingPeriodCaption(for id: PremiumProductId) -> String? {
        guard let period = products[id]?.subscription?.subscriptionPeriod else { return nil }
        return "iap.perPeriod".localized(Self.periodPhrase(period))
    }

    /// Lower-cased billing period for sentences, e.g. "then $11.99/month".
    func billingPeriodSuffix(for id: PremiumProductId) -> String? {
        guard let period = products[id]?.subscription?.subscriptionPeriod else { return nil }
        return Self.periodPhrase(period)
    }

    /// The product's free trial, but only when this account can still use it. A trial the
    /// customer has already spent is not offered again, so the paywall must not promise one.
    func freeTrial(for id: PremiumProductId) -> Product.SubscriptionOffer? {
        guard let offer = products[id]?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial,
              introEligibility[id] == true else { return nil }

        return offer
    }

    /// "3-Day Free Trial" for the plan cards, written from the offer's own period.
    func trialBadgeText(for id: PremiumProductId) -> String? {
        guard let offer = freeTrial(for: id) else { return nil }
        return "iap.trialBadge".localized(Self.hyphenatedDuration(offer.period))
    }

    /// "Try Free for 3 Days, then $11.99/month" — the line above the call to action.
    func trialSummary(for id: PremiumProductId) -> String? {
        guard let offer = freeTrial(for: id),
              let price = displayPrice(for: id),
              let period = billingPeriodSuffix(for: id) else { return nil }

        return "iap.trialSummary".localized(Self.durationText(offer.period), price, period)
    }

    /// The same line for a plan with no trial, so the button is never unexplained.
    func priceSummary(for id: PremiumProductId) -> String? {
        guard let price = displayPrice(for: id),
              let period = billingPeriodSuffix(for: id) else { return nil }

        return "iap.priceSummary".localized(price, period)
    }

    /// Asks the App Store which introductory offers this account can still use.
    func refreshIntroEligibility(for products: [PremiumProductId: Product]) async {
        var eligibility: [PremiumProductId: Bool] = [:]

        for (id, product) in products {
            guard let subscription = product.subscription else { continue }
            eligibility[id] = await subscription.isEligibleForIntroOffer
        }

        introEligibility = eligibility
    }

//    MARK: Period Formatting

    /// "3 Days", "1 Week", written from the offer's own period so a change in App Store
    /// Connect reads through without a code change.
    static func durationText(_ period: Product.SubscriptionPeriod) -> String {
        "\(period.value) " + unitName(period.unit, plural: period.value > 1)
    }

    /// "3-Day", the compact form the plan badge uses.
    static func hyphenatedDuration(_ period: Product.SubscriptionPeriod) -> String {
        "\(period.value)-" + unitName(period.unit, plural: false)
    }

    /// "week", "month", "7 weeks" — the plain-language length of a billing period. A weekly
    /// plan is sold as seven days, so periods are reduced to their natural unit first and the
    /// count is only spelled out when it is not one.
    static func periodPhrase(_ period: Product.SubscriptionPeriod) -> String {
        let (value, unit) = normalized(period)

        guard value > 1 else {
            return unitName(unit, plural: false).lowercased()
        }

        return "\(value) " + unitName(unit, plural: true).lowercased()
    }

    /// Seven days is a week, twelve months is a year. Anything else is left as the store set it.
    private static func normalized(_ period: Product.SubscriptionPeriod) -> (Int, Product.SubscriptionPeriod.Unit) {
        switch period.unit {
        case .day where period.value % 7 == 0:
            return (period.value / 7, .week)
        case .month where period.value % 12 == 0:
            return (period.value / 12, .year)
        default:
            return (period.value, period.unit)
        }
    }

    /// Singular and plural are separate keys rather than a suffixed "s": most
    /// languages do not pluralise by appending a letter.
    static func unitName(_ unit: Product.SubscriptionPeriod.Unit, plural: Bool) -> String {
        let stem: String

        switch unit {
        case .day:
            stem = "day"
        case .week:
            stem = "week"
        case .month:
            stem = "month"
        case .year:
            stem = "year"
        @unknown default:
            stem = "period"
        }

        return "iap.unit.\(stem)\(plural ? "s" : "")".localized
    }
}


// MARK: - Paywall Selection
//
//  Which plan the paywall opens on, and whether the button may promise a free
//  trial. Both answers come from the products the App Store actually returned
//  and from this account's introductory-offer eligibility, so the paywall
//  never promises a trial the customer has already spent.

extension PremiumProductId {

    /// The plan's name on its card. The store's own `displayName` is whatever
    /// was typed into App Store Connect, so the short design label is kept here.
    var planTitle: String {
        switch self {
        case .weekly: return "plan.weekly".localized
        case .monthly: return "plan.monthly".localized
        case .yearly: return "plan.yearly".localized
        }
    }
}

extension IAPManager {

    /// The plans the store returned, in the order the paywall lists them. A
    /// product missing from App Store Connect simply drops out of the grid.
    var availablePlans: [PremiumProductId] {
        Self.planOrder.filter { products[$0] != nil }
    }

    /// True once at least one plan has arrived. The paywall shows placeholders
    /// until then rather than guessing at prices.
    var hasLoadedPlans: Bool { !availablePlans.isEmpty }

    /// Whether this account can still start a free trial on the plan.
    func hasFreeTrial(_ id: PremiumProductId) -> Bool {
        freeTrial(for: id) != nil
    }

    /// Whether any plan on offer carries a trial this account can still use.
    var hasAnyFreeTrial: Bool {
        availablePlans.contains { hasFreeTrial($0) }
    }

    /// The plan the paywall opens on.
    ///
    /// A usable trial decides it, so the customer lands on the plan the button
    /// is about to offer them. Monthly breaks a tie because the design marks it
    /// most popular; otherwise the listed order does. With no trial on offer
    /// Monthly is the default, falling back to the first plan the store
    /// returned if Monthly itself is unavailable.
    ///
    /// `nil` while products are still loading — there is nothing valid to pick.
    var defaultPlan: PremiumProductId? {
        let withTrial = availablePlans.filter { hasFreeTrial($0) }

        if !withTrial.isEmpty {
            return withTrial.contains(.monthly) ? .monthly : withTrial.first
        }

        return availablePlans.contains(.monthly) ? .monthly : availablePlans.first
    }

    /// The caption under a plan's price: its trial when it has one, the saving
    /// when the longer plan is cheaper by the month, and otherwise how often it
    /// bills.
    func planCaption(for id: PremiumProductId) -> String? {
        if let badge = trialBadgeText(for: id) { return badge }

        if let monthly = monthlyEquivalent(for: id) {
            if let saving = savingsPercent(for: id) {
                return "iap.caption.savings".localized(monthly, saving)
            }
            return "iap.caption.monthlyEquivalent".localized(monthly)
        }

        guard let cadence = billingCadence(for: id) else { return nil }
        return "iap.caption.billed".localized(cadence)
    }

    /// "weekly", "monthly", "yearly" — how often the plan charges.
    func billingCadence(for id: PremiumProductId) -> String? {
        switch products[id]?.subscription?.subscriptionPeriod.unit {
        case .day, .week: return "iap.cadence.weekly".localized
        case .month: return "iap.cadence.monthly".localized
        case .year: return "iap.cadence.yearly".localized
        default: return nil
        }
    }

    // MARK: Price Comparison
    //
    //  A yearly plan is sold on what it costs per month, so the figure and the
    //  saving are divided out of the store's own price rather than written down
    //  beside it, where they would drift the moment a price changes.

    /// The plan's price reduced to one month, in the store's currency. `nil`
    /// for plans that bill monthly or more often, which have nothing to reduce.
    func monthlyEquivalent(for id: PremiumProductId) -> String? {
        guard let product = products[id],
              let period = product.subscription?.subscriptionPeriod,
              let months = Self.months(in: period), months > 1 else { return nil }

        return (product.price / months).formatted(product.priceFormatStyle)
    }

    /// How much cheaper the plan is per month than the monthly plan, rounded
    /// down to a whole percent. `nil` unless both plans are loaded, share a
    /// currency and the saving is real.
    func savingsPercent(for id: PremiumProductId) -> Int? {
        guard let product = products[id],
              let monthly = products[.monthly],
              product.priceFormatStyle.currencyCode == monthly.priceFormatStyle.currencyCode,
              let period = product.subscription?.subscriptionPeriod,
              let months = Self.months(in: period), months > 1,
              monthly.price > 0 else { return nil }

        let perMonth = product.price / months
        let saving = (1 - perMonth / monthly.price) * 100
        let percent = (saving as NSDecimalNumber).intValue

        return percent > 0 ? percent : nil
    }

    /// A billing period counted in months, or `nil` for the shorter units that
    /// do not divide into one.
    private static func months(in period: Product.SubscriptionPeriod) -> Decimal? {
        switch period.unit {
        case .year: return Decimal(period.value * 12)
        case .month: return Decimal(period.value)
        default: return nil
        }
    }
}


// MARK: - Launch Gating
//
//  The paywall is offered a moment after launch, and only to customers who are
//  not already subscribed. Entitlements are the authority on that, so the check
//  waits for verification to finish rather than reading the stored flag, which
//  is only a cache of the last answer.

extension IAPManager {

    /// How long the app settles before the paywall is offered.
    static let launchPaywallDelay: TimeInterval = 1.5

    /// Whether the paywall should be presented at launch.
    ///
    /// Waits out the settling delay, then waits for entitlement verification,
    /// so a subscriber never sees the paywall flash before it is dismissed.
    func shouldPresentPaywallAtLaunch() async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(Self.launchPaywallDelay * 1_000_000_000))
        await waitForVerification()

        return !isPremiumUnlocked
    }

    /// Blocks until the entitlement check started at init finishes, or until it
    /// has taken too long to keep waiting on — a store that never answers must
    /// not leave a non-subscriber without the paywall for ever.
    func waitForVerification(timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)

        while isVerifying && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
