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

    var description: LocalizedStringKey {
        switch self {
        case .everyAppLaunch:
            "Every App Launch"
        case .everyThreeDays:
            "Every 3 Days"
        case .weekly:
            "Weekly"
        case .monthly:
            "Monthly"
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

    func shouldLoadFromCache(at cacheURL: URL) throws -> Bool {
        if self == .everyAppLaunch {
            return false
        }

        let fileManager = FileManager.default

        // Check if cache file exists
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return false
        }

        let fileAttributes = try cacheURL.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modificationDate = fileAttributes.contentModificationDate else {
            return false
        }

        // Calculate time difference
        let timeSinceLastUpdate = Date().timeIntervalSince(modificationDate)

        // Return true if the cache is still fresh
        return timeSinceLastUpdate < self.timeInterval
    }
}
