//
//  UpdateButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct UpdateButton: View {
    var cask: CaskViewModel
    @Environment(CaskManager.self) var caskManager

    var body: some View {
        Button {
            caskManager.update(cask)
        } label: {
            Label("Update", systemImage: "arrow.triangle.2.circlepath")
        }
        .cardActionPill()
        .disabled(cask.homebrewManagementBlockReason != nil || cask.isManagementProtected)
        .help(cask.homebrewManagementBlockReason ?? String(localized: "Update with Homebrew"))
    }
}
