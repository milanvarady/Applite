//
//  InstalledView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import Fuse

/// Shows installed apps, where the user can open and uninstall them
struct InstalledView: View {
    @EnvironmentObject var caskManager: CaskManager
    @State var searchText = ""
    
    let fuseSearch = Fuse()
    
    var body: some View {
        VStack {
            ScrollView {
                AppGridView(casks: casks, appRole: .installed)
                    .padding()
            }
        }
        .searchable(text: $searchText)
        .id("InstalledView")
    }

    // Filter installed casks
    var casks: [Cask] {
        var installedCasks = caskManager.installedCasks

        if !$searchText.wrappedValue.isEmpty {
            installedCasks = installedCasks.filter {
                (fuseSearch.search(searchText, in: $0.info.name)?.score ?? 1) < 0.4
            }
        }

        let installedCasksAlphabetical = installedCasks.sorted { $0.info.name < $1.info.name }

        return installedCasksAlphabetical
    }
}

struct InstalledView_Previews: PreviewProvider {
    static var previews: some View {
        InstalledView()
            .environmentObject(CaskManager())
    }
}
