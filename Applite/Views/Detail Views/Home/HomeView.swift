//
//  HomeView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

struct HomeView: View {
    @Binding var navigationSelection: SidebarItem

    var body: some View {
        DiscoverView(navigationSelection: $navigationSelection)
    }
}
