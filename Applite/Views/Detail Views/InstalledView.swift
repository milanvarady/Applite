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
    @EnvironmentObject var caskData: CaskData
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
    }
    
    // Filter installed casks
    var casks: [Cask] {
        var filteredCasks = caskData.casks.filter { $0.isInstalled }
        
        if !$searchText.wrappedValue.isEmpty {
            filteredCasks = filteredCasks.filter {
                (fuseSearch.search(searchText, in: $0.name)?.score ?? 1) < 0.4
            }
        }
        
        return filteredCasks
    }
}

struct InstalledView_Previews: PreviewProvider {
    static var previews: some View {
        InstalledView()
            .environmentObject(CaskData())
    }
}
