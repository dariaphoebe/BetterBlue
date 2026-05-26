//
//  AppSettings.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 8/3/25.
//

import BetterBlueKit
import Foundation
import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
    import ActivityKit
#endif

#if canImport(UserNotifications)
    import UserNotifications
#endif

enum WidgetRefreshInterval: Int, CaseIterable {
    case oneHour = 1
    case twoHours = 2
    case threeHours = 3
    case fourHours = 4
    case sixHours = 6
    case twelveHours = 12

    var displayName: String {
        switch self {
        case .oneHour:
            return "1 hour"
        case .twoHours:
            return "2 hours"
        case .threeHours:
            return "3 hours"
        case .fourHours:
            return "4 hours"
        case .sixHours:
            return "6 hours"
        case .twelveHours:
            return "12 hours"
        }
    }

    var timeInterval: TimeInterval {
        return TimeInterval(rawValue * 3600) // Convert hours to seconds
    }
}

/// Protocol to abstract storage for cross-device sync (iCloud on device, shared file in simulator)
private protocol SyncStore {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
    func performSync()
}

extension NSUbiquitousKeyValueStore: SyncStore {
    func setString(_ value: String, forKey key: String) {
        set(value as Any, forKey: key)
    }

    func performSync() {
        synchronize()
    }
}

/// Shared UserDefaults-based sync store for simulator (uses /tmp/BetterBlue_Shared)
private final class SimulatorSyncStore: SyncStore {
    private let defaults: UserDefaults

    init() {
        let sharedPath = "/tmp/BetterBlue_Shared"
        try? FileManager.default.createDirectory(
            atPath: sharedPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
        // Use a UserDefaults with a custom suite that points to the shared location
        defaults = UserDefaults(suiteName: sharedPath) ?? UserDefaults.standard
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func performSync() {
        defaults.synchronize()
    }
}

@MainActor @Observable
class AppSettings {
    static let shared = AppSettings()

    private let userDefaults = UserDefaults(suiteName: "group.com.betterblue.shared")!
    private let syncStore: SyncStore
    private let isSimulator: Bool
    private let distanceUnitKey = "DistanceUnit"
    private let temperatureUnitKey = "TemperatureUnit"
    private let notificationsEnabledKey = "NotificationsEnabled"
    private let widgetRefreshIntervalKey = "WidgetRefreshInterval"
    private let debugModeEnabledKey = "DebugModeEnabled"
    private let liveActivitiesEnabledKey = "LiveActivitiesEnabled"

    var preferredDistanceUnit: Distance.Units {
        didSet {
            // Write to both sync store (for cross-device sync) and UserDefaults (for widgets)
            syncStore.setString(preferredDistanceUnit.rawValue, forKey: distanceUnitKey)
            userDefaults.set(preferredDistanceUnit.rawValue, forKey: distanceUnitKey)
            syncStore.performSync()
            refreshWidgetsAndLiveActivities()
        }
    }

    var preferredTemperatureUnit: Temperature.Units {
        didSet {
            // Write to both sync store (for cross-device sync) and UserDefaults (for widgets)
            syncStore.setString(preferredTemperatureUnit.rawValue, forKey: temperatureUnitKey)
            userDefaults.set(preferredTemperatureUnit.rawValue, forKey: temperatureUnitKey)
            syncStore.performSync()
            refreshWidgetsAndLiveActivities()
        }
    }

    // MARK: - Live cross-process reads
    //
    // `AppSettings.shared` is a process-lifetime singleton — its
    // stored properties are populated ONCE at first access and
    // never re-read from UserDefaults. That's fine for the main
    // app (any change goes through `didSet` in the same process)
    // but breaks widget / Live Activity / App Intent extensions:
    // those run in a separate process that iOS keeps alive across
    // multiple timeline reloads, so their in-memory copy of
    // `preferredDistanceUnit` stays at whatever it was when the
    // extension process first launched. Even after the main app
    // wrote the new value to App Group UserDefaults, the widget
    // process's singleton kept returning the old one.
    //
    // The two `live*` accessors below skip the singleton and read
    // App Group UserDefaults directly each time, so extensions
    // always reflect the latest setting on their next reload.

    nonisolated private static let appGroupSuiteName = "group.com.betterblue.shared"
    nonisolated private static let distanceUnitKey = "DistanceUnit"
    nonisolated private static let temperatureUnitKey = "TemperatureUnit"

    // `nonisolated` because UserDefaults reads are thread-safe and
    // these callers (widget timeline provider, intent perform
    // methods) are explicitly NOT on the main actor. The enclosing
    // type is @MainActor for the Observable property storage.
    nonisolated static func liveDistanceUnit() -> Distance.Units {
        guard let defaults = UserDefaults(suiteName: appGroupSuiteName),
              let raw = defaults.string(forKey: distanceUnitKey),
              let unit = Distance.Units(rawValue: raw) else {
            return .miles
        }
        return unit
    }

    nonisolated static func liveTemperatureUnit() -> Temperature.Units {
        guard let defaults = UserDefaults(suiteName: appGroupSuiteName),
              let raw = defaults.string(forKey: temperatureUnitKey),
              let unit = Temperature.Units(rawValue: raw) else {
            return .fahrenheit
        }
        return unit
    }

    var notificationsEnabled: Bool {
        didSet {
            userDefaults.set(notificationsEnabled, forKey: notificationsEnabledKey)
            if notificationsEnabled {
                #if canImport(UserNotifications)
                    Task {
                        await requestNotificationPermission()
                    }
                #endif
            }
        }
    }

    var widgetRefreshInterval: WidgetRefreshInterval {
        didSet {
            userDefaults.set(widgetRefreshInterval.rawValue, forKey: widgetRefreshIntervalKey)
        }
    }

    var debugModeEnabled: Bool {
        didSet {
            userDefaults.set(debugModeEnabled, forKey: debugModeEnabledKey)
        }
    }

    var liveActivitiesEnabled: Bool {
        didSet {
            userDefaults.set(liveActivitiesEnabled, forKey: liveActivitiesEnabledKey)
        }
    }

    private init() {
        #if targetEnvironment(simulator)
            isSimulator = true
            syncStore = SimulatorSyncStore()
        #else
            isSimulator = false
            syncStore = NSUbiquitousKeyValueStore.default
        #endif

        // Read App Group UserDefaults FIRST, iCloud second. The
        // widget extension is a separate process from the main app,
        // and `NSUbiquitousKeyValueStore` keeps its own per-process
        // local cache that lags behind the main app's writes until
        // iCloud delivers a change notification. App Group
        // UserDefaults, by contrast, is shared synchronously across
        // processes on the same device — writes from the main app
        // are immediately visible to the widget. iCloud remains the
        // cross-device source (picked up below in `handleiCloudChange`),
        // but UserDefaults is the source of truth for "what this
        // device's main app last saved."
        let savedDistanceUnit = userDefaults.string(forKey: distanceUnitKey)
            ?? syncStore.string(forKey: distanceUnitKey)
            ?? Distance.Units.miles.rawValue
        preferredDistanceUnit = Distance.Units(rawValue: savedDistanceUnit) ?? .miles

        let savedTemperatureUnit = userDefaults.string(forKey: temperatureUnitKey)
            ?? syncStore.string(forKey: temperatureUnitKey)
            ?? Temperature.Units.fahrenheit.rawValue
        preferredTemperatureUnit = Temperature.Units(rawValue: savedTemperatureUnit) ?? .fahrenheit

        notificationsEnabled = userDefaults.bool(forKey: notificationsEnabledKey)

        let savedRefreshInterval = userDefaults.integer(forKey: widgetRefreshIntervalKey)
        widgetRefreshInterval = WidgetRefreshInterval(rawValue: savedRefreshInterval) ?? .fourHours

        if userDefaults.object(forKey: debugModeEnabledKey) == nil {
            #if DEBUG
                debugModeEnabled = true
            #else
                debugModeEnabled = false
            #endif
        } else {
            debugModeEnabled = userDefaults.bool(forKey: debugModeEnabledKey)
        }

        // Live Activities is a beta feature, disabled by default
        liveActivitiesEnabled = userDefaults.bool(forKey: liveActivitiesEnabledKey)

        // Start sync store and listen for changes from other devices
        syncStore.performSync()

        #if !targetEnvironment(simulator)
            // Only set up iCloud observer on real devices
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default,
                queue: .main
            ) { [weak self] notification in
                // Extract values from notification before async boundary
                guard let self,
                      let userInfo = notification.userInfo,
                      let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
                      let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
                    return
                }
                Task { @MainActor [self] in
                    self.handleiCloudChange(changeReason: changeReason, changedKeys: changedKeys)
                }
            }
        #endif
    }

    private func handleiCloudChange(changeReason: Int, changedKeys: [String]) {
        BBLogger.info(.app, "iCloud settings changed externally (reason: \(changeReason)): \(changedKeys)")

        // Update stored properties from iCloud values. The didSet
        // observers on `preferredDistanceUnit` /
        // `preferredTemperatureUnit` will re-write to App Group
        // UserDefaults as a side effect — ensuring the local
        // widget extension picks up cross-device changes too. If
        // we updated only the in-memory value, the widget process
        // would still read the old UserDefaults value on its next
        // timeline reload.
        if changedKeys.contains(distanceUnitKey),
           let value = syncStore.string(forKey: distanceUnitKey),
           let unit = Distance.Units(rawValue: value),
           unit != preferredDistanceUnit {
            preferredDistanceUnit = unit
        }

        if changedKeys.contains(temperatureUnitKey),
           let value = syncStore.string(forKey: temperatureUnitKey),
           let unit = Temperature.Units(rawValue: value),
           unit != preferredTemperatureUnit {
            preferredTemperatureUnit = unit
        }
    }

    private func requestNotificationPermission() async {
        #if canImport(UserNotifications)
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    BBLogger.info(.push, "Notifications: Permission granted")
                } else {
                    BBLogger.warning(.push, "Notifications: Permission denied")
                    await MainActor.run {
                        notificationsEnabled = false
                    }
                }
            } catch {
                BBLogger.error(.push, "Notifications: Permission request failed: \(error)")
                await MainActor.run {
                    notificationsEnabled = false
                }
            }
        #endif
    }

    private func refreshWidgetsAndLiveActivities() {
        
        // Refresh all widgets to pick up the new unit settings
        BBLogger.info(.app, "Refreshing widget and live activities")
        WidgetCenter.shared.reloadAllTimelines()

        // Refresh all live activities to pick up the new unit settings
        #if canImport(ActivityKit)
            Task { @MainActor in
                for activity in Activity<VehicleActivityAttributes>.activities {
                    let currentState = activity.content.state
                    await activity.update(ActivityContent(state: currentState, staleDate: nil))
                }
            }
        #endif
    }
}
