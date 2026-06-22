//
//  SidebarItem.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.30.
//

import Foundation

enum SidebarItem: Equatable, Hashable {
    case home
    case updates
    case installed
    case activeTasks
    case appMigration
    case brew
    /// Tied to the static `Category` id rather than the loaded `CategoryLoadResult`,
    /// so the detail view can re-resolve the freshest casks each render — critical for
    /// the placeholder→full transition during catalog load.
    case appCategory(id: CategoryId)
    case tap(tap: TapLoadResult)
}
