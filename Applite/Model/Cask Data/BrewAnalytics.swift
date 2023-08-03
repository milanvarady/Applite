//
//  BrewAnalytics.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 12..
//

import Foundation

/// Used when decoding download count analytics from Homebrew API
struct BrewAnalytics: Decodable {
    let items: [AnalyticsItem]
}

/// Used in the ``BrewAnalytics`` object to decode cask download count data
struct AnalyticsItem: Decodable {
    let cask, count: String
}
