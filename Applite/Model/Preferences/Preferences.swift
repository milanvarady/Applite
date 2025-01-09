//
//  Preferences.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 18..
//

import Foundation

enum Preferences: String {
    // Setup
    case setupComplete

    // General
    case colorSchemePreference
    case notificationSuccess
    case notificationFailure

    // Brew
    case brewPathOption
    case customUserBrewPath
    case includeCasksFromTaps
    case appdirOn
    case appdirPath
    case noQuarantine

    // Proxy
    case networkProxyEnabled
    case preferredProxyType
}
