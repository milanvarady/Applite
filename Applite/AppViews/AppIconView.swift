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
    var size: CGFloat = 54

    var body: some View {
        if state != .failed {
            KFImage.url(state == .showingAppIcon ? iconURL : faviconURL, cacheKey: cacheKey)
                .resizable()
                .placeholder {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.gray)
                        .shimmering()
                }
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: size, height: size)
        } else {
            // App icon missing
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.gray, lineWidth: 3)

                Text("?")
                    .font(.system(size: size * 0.44, weight: .light))
            }
            .foregroundStyle(.gray)
            .frame(width: size * 0.74, height: size * 0.74)
        }
    }
}
