//
//  DownloadView+NoSearchResults.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension DownloadView {
    var noSearchResults: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.red)
                    .font(.appliteMediumTitle)

                Text("\"\(searchText)\" didn't match any app. Either it's not available in the Homebrew catalog or you misspelled it.")
                    .font(.system(size: 20))
            }

            .padding(.bottom)

            // Turn of filtering
            if hideUnpopularApps {
                Button {
                    hideUnpopularApps = false
                } label: {
                    Label("Turn off few downloads filter", systemImage: "slider.horizontal.2.square.on.square")
                }
                .controlSize(.large)
                .help("Apps with few downloads are hidden, consider turning off this filter")
            }
        }
    }
}
