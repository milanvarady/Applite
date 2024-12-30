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
    case appCategory(categoryId: String)
}
