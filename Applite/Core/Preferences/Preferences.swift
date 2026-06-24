//
//  Preferences.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 18..
//

import SwiftUI

/// A type-safe UserDefaults preference key that bundles its storage name, value type, and default value.
///
/// This is the single source of truth for a preference: define the key once in ``Preferences`` and
/// the default travels with it to every call site, so two views can't drift to different defaults.
struct PreferenceKey<Value: Sendable>: Sendable {
    let name: String
    let defaultValue: Value

    init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// Single source of truth for all UserDefaults-backed preferences.
///
/// Read in SwiftUI with `@AppStorage(Preferences.someKey)` and outside SwiftUI with
/// `UserDefaults.standard.value(for: Preferences.someKey)`. The default is defined here, once.
enum Preferences {
    // Setup
    static let setupComplete = PreferenceKey("setupComplete", default: false)

    // General
    static let colorSchemePreference = PreferenceKey("colorSchemePreference", default: ColorSchemePreference.system)
    static let catalogUpdateFrequency = PreferenceKey("catalogUpdateFrequency", default: CatalogUpdateFrequency.default)
    static let notificationSuccess = PreferenceKey("notificationSuccess", default: false)
    static let notificationFailure = PreferenceKey("notificationFailure", default: true)

    // Brew
    static let brewPathOption = PreferenceKey("brewPathOption", default: BrewPaths.PathOption.appPath.rawValue)
    static let customUserBrewPath = PreferenceKey("customUserBrewPath", default: "/opt/homebrew/bin/brew")
    static let includeCasksFromTaps = PreferenceKey("includeCasksFromTaps", default: true)
    static let appdirOn = PreferenceKey("appdirOn", default: false)
    static let appdirPath = PreferenceKey("appdirPath", default: "/Applications")
    static let greedyUpgrade = PreferenceKey("greedyUpgrade", default: false)
    static let noQuarantine = PreferenceKey("noQuarantine", default: false)

    // Proxy
    static let networkProxyEnabled = PreferenceKey("networkProxyEnabled", default: true)
    static let preferredProxyType = PreferenceKey("preferredProxyType", default: NetworkProxyType.http)

    // Mirrors
    static let mirrorEnabled = PreferenceKey("mirrorEnabled", default: false)
    static let mirrorAPIDomain = PreferenceKey("mirrorAPIDomain", default: "")
    static let mirrorBrewGitRemote = PreferenceKey("mirrorBrewGitRemote", default: "")
    static let mirrorCoreGitRemote = PreferenceKey("mirrorCoreGitRemote", default: "")
    static let mirrorBottleDomain = PreferenceKey("mirrorBottleDomain", default: "")

    // Sorting options
    static let searchSortOption = PreferenceKey("searchSortOption", default: SortingOptions.mostDownloaded)
    static let hideUnpopularApps = PreferenceKey("hideUnpopularApps", default: false)
    static let hideDisabledApps = PreferenceKey("hideDisabledApps", default: false)
}

// MARK: - SwiftUI @AppStorage support

extension AppStorage {
    init(_ key: PreferenceKey<Value>) where Value == Bool {
        self.init(wrappedValue: key.defaultValue, key.name)
    }

    init(_ key: PreferenceKey<Value>) where Value == Int {
        self.init(wrappedValue: key.defaultValue, key.name)
    }

    init(_ key: PreferenceKey<Value>) where Value == String {
        self.init(wrappedValue: key.defaultValue, key.name)
    }

    init(_ key: PreferenceKey<Value>) where Value: RawRepresentable, Value.RawValue == String {
        self.init(wrappedValue: key.defaultValue, key.name)
    }

    init(_ key: PreferenceKey<Value>) where Value: RawRepresentable, Value.RawValue == Int {
        self.init(wrappedValue: key.defaultValue, key.name)
    }
}

// MARK: - Non-SwiftUI UserDefaults access

extension UserDefaults {
    /// Reads a preference, returning its defined default value when the key is unset.
    func value(for key: PreferenceKey<Bool>) -> Bool {
        object(forKey: key.name) as? Bool ?? key.defaultValue
    }

    /// Reads a preference, returning its defined default value when the key is unset.
    func value(for key: PreferenceKey<String>) -> String {
        object(forKey: key.name) as? String ?? key.defaultValue
    }

    /// Reads a preference, returning its defined default value when the key is unset.
    func value(for key: PreferenceKey<Int>) -> Int {
        object(forKey: key.name) as? Int ?? key.defaultValue
    }

    /// Reads a `RawRepresentable` preference (Int-backed enum), returning its default when the key is unset or invalid.
    func value<Value: RawRepresentable & Sendable>(for key: PreferenceKey<Value>) -> Value where Value.RawValue == Int {
        (object(forKey: key.name) as? Int).flatMap(Value.init(rawValue:)) ?? key.defaultValue
    }

    /// Reads a `RawRepresentable` preference (String-backed enum), returning its default when the key is unset or invalid.
    func value<Value: RawRepresentable & Sendable>(for key: PreferenceKey<Value>) -> Value where Value.RawValue == String {
        (object(forKey: key.name) as? String).flatMap(Value.init(rawValue:)) ?? key.defaultValue
    }

    /// Writes a preference value.
    func setValue<Value>(_ value: Value, for key: PreferenceKey<Value>) {
        set(value, forKey: key.name)
    }
}
