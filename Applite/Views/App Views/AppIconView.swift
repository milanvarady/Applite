//
//  AppIconView.swift
//  Applite
//
//  Created by Milán Várady on 05/04/2024.
//

import SwiftUI
import Kingfisher
import Shimmer

enum AppIconState {
    case showingAppIcon
    case showingFavicon
    case failed
}

struct AppIconView: View {
    @State private var state: AppIconState = .showingAppIcon

    let iconURL: URL
    let faviconURL: URL
    let cacheKey: String

    var body: some View {
        if state != .failed {
            KFImage.url(state == .showingAppIcon ? iconURL : faviconURL, cacheKey: cacheKey)
                .resizable()
                .placeholder {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.gray)
                        .shimmering()
                }
                .setProcessor(RoundCornerImageProcessor(cornerRadius: 8)) // Round corners
                .fade(duration: 0.25)
                .onFailure { error in
                    // Change state
                    switch state {
                    case .showingAppIcon:
                        state = .showingFavicon
                    case .showingFavicon:
                        state = .failed
                    default:
                        state = .failed
                    }
                }
                .frame(width: 54, height: 54)
        } else {
            // App icon missing
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.gray, lineWidth: 3)

                Text("?")
                    .font(.system(size: 24, weight: .light))
            }
            .foregroundStyle(.gray)
            .frame(width: 40, height: 40)
        }
    }
}
