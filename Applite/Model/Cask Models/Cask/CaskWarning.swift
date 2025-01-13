//
//  CaskWarning.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.13.
//

import SwiftUI

enum CaskWarning: Codable {
    case hasCaveat(caveat: String)
    case deprecated(date: String, reason: String)
    case disabled(date: String, reason: String)

    var title: LocalizedStringKey {
        switch self {
        case .hasCaveat: return "App has Caveats"
        case .deprecated: return "App is Deprecated"
        case .disabled: return "App is Disabled"
        }
    }

    var isDisabled: Bool {
        switch self {
        case .hasCaveat, .deprecated: return false
        case .disabled: return true
        }
    }
}
