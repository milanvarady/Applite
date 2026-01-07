//
//  SidebarItem.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.30.
// MODIFIED by Subham mahesh EVERY MODIFICATION MADE BY SUBHAM MAHESH LICENSE UNDER THE MIT

//

import Foundation

enum SidebarItem: Equatable, Hashable {
    case home
    case updates
    case installed
    case activeTasks
    case appMigration
    case packageManager
    case brew
    case appCategory(category: CategoryViewModel)
    case tap(tap: TapViewModel)
}
