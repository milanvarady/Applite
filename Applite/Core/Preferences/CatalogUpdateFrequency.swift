//
//  CatalogUpdateFrequency.swift
//  Applite
//
//  Created by Milán Várady on 2025.02.19.
//

import Foundation
import SwiftUI

enum CatalogUpdateFrequency: Int, CaseIterable, Identifiable {
    case everyAppLaunch
    case everyThreeDays
    case weekly
    case monthly

    static let `default`: CatalogUpdateFrequency = .everyThreeDays

    var description: LocalizedStringKey {
        switch self {
        case .everyAppLaunch:
            "App launch"
        case .everyThreeDays:
            "3 days"
        case .weekly:
            "Week"
        case .monthly:
            "Month"
        }
    }

    var id: Self {
        self
    }

    var timeInterval: TimeInterval {
        switch self {
        case .everyAppLaunch:
            return 0
        case .everyThreeDays:
            return 3 * 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .monthly:
            return 30 * 24 * 60 * 60
        }
    }
}
