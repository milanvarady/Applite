//
//  BrewAnalytics.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 12..
//

import Foundation

/// Used when decoding download count analytics from Homebrew API
struct BrewAnalytics: Codable {
    let items: [AnalyticsItem]
}

/// Used in the ``BrewAnalytics`` object to decode cask download count data
struct AnalyticsItem: Codable {
    let cask, count: String
}
