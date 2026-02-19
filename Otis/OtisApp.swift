// OtisApp.swift
// Otis — AI-powered travel packing companion
// Bundle ID: com.bouquetgarden.otis
// iOS 17+ minimum deployment target

import SwiftUI
import SwiftData
import RevenueCat

@main
struct OtisApp: App {

    // MARK: - Subscription Manager
    @StateObject private var subscriptionManager = SubscriptionManager()

    // MARK: - SwiftData Model Container
    /// Configured with CloudKit for Pro subscribers.
    /// Schema includes all persistent models. CloudKit container is always
    /// registered so the entitlement is exercised from first launch — sync
    /// is activated/deactivated based on subscription status at runtime.
    static let modelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self,
            PackingItem.self,
            PackingProfile.self,
            Stamp.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(AppConfig.cloudKitContainerID)
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // A fatal error here means the schema is corrupt or device storage is
            // completely unavailable — both are unrecoverable at launch.
            fatalError("Otis: Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subscriptionManager)
        }
        .modelContainer(OtisApp.modelContainer)
    }

    // MARK: - Init

    init() {
        configureRevenueCat()
    }

    // MARK: - Private Helpers

    private func configureRevenueCat() {
        // API key is injected via xcconfig → Info.plist → AppConfig at build time.
        // The key is never committed to source control.
        let apiKey = AppConfig.revenueCatAPIKey

        guard !apiKey.isEmpty else {
            // During early development without a real key, RevenueCat is not
            // configured. SubscriptionManager will fall back to free-tier state.
            print("Otis [RevenueCat]: API key not set — running in free-tier simulation mode.")
            return
        }

        Purchases.logLevel = AppConfig.isDebug ? .debug : .warn
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = PurchasesDelegate.shared
    }
}

// MARK: - RevenueCat Delegate

/// Singleton delegate that forwards subscription updates to SubscriptionManager
/// via NotificationCenter, keeping RevenueCat isolated from SwiftUI state.
final class PurchasesDelegate: NSObject, PurchasesDelegate {

    static let shared = PurchasesDelegate()

    private override init() { super.init() }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        NotificationCenter.default.post(
            name: .subscriptionStatusDidChange,
            object: customerInfo
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let subscriptionStatusDidChange = Notification.Name("OtisSubscriptionStatusDidChange")
}
