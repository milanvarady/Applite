//
//  HomeView+NoSearchResults.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

extension HomeView {
    struct NoSearchResults: View {
        @Binding var searchText: String
        @AppStorage("hideUnpopularApps") var hideUnpopularApps = false

        var body: some View {
            VStack {
                VStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.appliteMediumTitle)

                        Text(
                            "\"\(searchText)\" didn't match any app. Either it's not available in the Homebrew catalog or you misspelled it.",
                            comment: "Empty search results message"
                        )
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
                .padding(.vertical, 50)

                Spacer()
            }
            .frame(maxWidth: 600)
        }
    }
}
