import Foundation
import HealthKit

/// Optional saving of each drink to Apple Health (as "Water").
///
/// Shared with the widget target, since its Add button and controls log drinks too.
/// Write-only: the app never reads Health data. Each drink goes into a small queue in the
/// shared store first and leaves it once Health accepts it, so a save that fails (for example
/// from the widget, or before permission is granted) is retried the next time the app becomes
/// active or another drink is logged.
nonisolated enum HealthSync {
    nonisolated enum Keys {
        static let enabled = "saveToHealth"
        static let pending = "pendingHealthDrinks"
    }

    /// A drink waiting to be saved to Health.
    nonisolated struct Drink: Codable, Equatable, Sendable {
        var id: UUID
        var date: Date
        var milliliters: Double
    }

    /// Drinks that still haven't been saved after this long are dropped, so the queue
    /// can't grow forever if Health access is turned off.
    static let maxPendingAge: TimeInterval = 7 * 24 * 60 * 60

    private static let store = HKHealthStore()
    private static let waterType = HKQuantityType(.dietaryWater)

    /// False on devices without the Health app (e.g. iPadOS 16) and where it's restricted.
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func isEnabled(in defaults: UserDefaults = SharedStore.defaults) -> Bool {
        defaults.bool(forKey: Keys.enabled)
    }

    /// True if the user has turned off this app's access in the Health app.
    static var isSharingDenied: Bool {
        isAvailable && store.authorizationStatus(for: waterType) == .sharingDenied
    }

    private static var isSharingAuthorized: Bool {
        isAvailable && store.authorizationStatus(for: waterType) == .sharingAuthorized
    }

    /// Shows the Health permission sheet (only the first time; iOS doesn't ask again).
    /// - Returns: true if the app may save water.
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [waterType], read: [])
        } catch {
            return false
        }
        return isSharingAuthorized
    }

    // MARK: Logging

    /// Queues a drink (if saving to Health is on) and saves everything waiting.
    static func log(_ amount: Int, unit: VolumeUnit, at date: Date,
                    defaults: UserDefaults = SharedStore.defaults) async {
        guard isEnabled(in: defaults), amount > 0 else { return }
        let drink = Drink(id: UUID(), date: date, milliliters: VolumeUnit.ml.convert(amount, from: unit))
        enqueue(drink, now: date, in: defaults)
        await savePending(defaults: defaults)
    }

    /// Saves every queued drink that Health will accept. Safe to call often.
    static func savePending(defaults: UserDefaults = SharedStore.defaults) async {
        guard isEnabled(in: defaults), isSharingAuthorized else { return }
        let drinks = pending(in: defaults)
        guard !drinks.isEmpty else { return }

        var saved = Set<UUID>()
        for drink in drinks {
            do {
                try await store.save(sample(for: drink))
                saved.insert(drink.id)
            } catch {
                // Left in the queue for the next attempt.
            }
        }
        removePending(in: defaults) { saved.contains($0.id) }
    }

    /// Removes the drinks this app saved to Health on `date`'s day, plus any still queued.
    /// Used by "Reset today's intake". (Health only lets an app delete its own samples.)
    static func deleteDrinks(onDayOf date: Date, calendar: Calendar = .current,
                             defaults: UserDefaults = SharedStore.defaults) async {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        removePending(in: defaults) { $0.date >= start && $0.date < end }

        guard isSharingAuthorized else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        _ = try? await store.deleteObjects(of: waterType, predicate: predicate)
    }

    /// One Health sample per drink. The sync identifier makes a repeat save of the same
    /// drink (e.g. by the app and the widget at once) replace it instead of adding a copy.
    private static func sample(for drink: Drink) -> HKQuantitySample {
        HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: drink.milliliters),
            start: drink.date,
            end: drink.date,
            metadata: [
                HKMetadataKeySyncIdentifier: drink.id.uuidString,
                HKMetadataKeySyncVersion: 1,
            ]
        )
    }

    // MARK: Queue (in the shared store, so the app and widget see the same one)

    static func pending(in defaults: UserDefaults = SharedStore.defaults) -> [Drink] {
        guard let data = defaults.data(forKey: Keys.pending) else { return [] }
        return (try? JSONDecoder().decode([Drink].self, from: data)) ?? []
    }

    /// Adds a drink and drops ones older than `maxPendingAge`.
    static func enqueue(_ drink: Drink, now: Date, in defaults: UserDefaults = SharedStore.defaults) {
        var drinks = pending(in: defaults).filter { now.timeIntervalSince($0.date) < maxPendingAge }
        drinks.append(drink)
        setPending(drinks, in: defaults)
    }

    /// Empties the queue (when saving to Health is turned off).
    static func clearPending(in defaults: UserDefaults = SharedStore.defaults) {
        defaults.removeObject(forKey: Keys.pending)
    }

    /// Re-reads the queue before writing it back, so drinks added meanwhile aren't lost.
    private static func removePending(in defaults: UserDefaults, where shouldRemove: (Drink) -> Bool) {
        let drinks = pending(in: defaults)
        let kept = drinks.filter { !shouldRemove($0) }
        if kept.count != drinks.count { setPending(kept, in: defaults) }
    }

    private static func setPending(_ drinks: [Drink], in defaults: UserDefaults) {
        if drinks.isEmpty {
            defaults.removeObject(forKey: Keys.pending)
        } else if let data = try? JSONEncoder().encode(drinks) {
            defaults.set(data, forKey: Keys.pending)
        }
    }
}
