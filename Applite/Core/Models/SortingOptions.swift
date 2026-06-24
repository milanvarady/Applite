//
//  SortingOptions.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

enum SortingOptions: String, CaseIterable, Identifiable {
    case mostDownloaded
    case bestMatch
    case aToZ

    var id: SortingOptions { self }

    var description: LocalizedStringKey {
        switch self {
        case .mostDownloaded: return "Most downloaded (default)"
        case .bestMatch: return "Best match"
        case .aToZ: return "A to Z"
        }
    }
}
