//
//  GreedyUpgradeToggle.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import SwiftUI

struct GreedyUpgradeToggle: View {
    @AppStorage(Preferences.greedyUpgrade.rawValue) var greedyUpgrade: Bool = false
    
    var body: some View {
        HStack {
            Toggle(isOn: $greedyUpgrade) {
                Text("Greedy Upgrade", comment: "Brew greedy flag toggle title")
            }
            
            InfoPopup(
                text: "Enabling greedy upgrade will list all outdated apps, even those that have built-in update mechanisms and handle their own updates.",
                extraPaddingForLines: 3
            )
        }
    }
}
