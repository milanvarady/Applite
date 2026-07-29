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
    case failed
}

struct AppIconView: View {
    @State private var state: AppIconState = .showingAppIcon

    let iconURL: URL
    let cacheKey: String
    let fallbackInitial: String

    var body: some View {
        if state == .showingAppIcon {
            KFImage.url(iconURL, cacheKey: cacheKey)
                .resizable()
                .placeholder {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.gray)
                        .shimmering()
                }
                .fade(duration: 0.25)
                .onFailure { _ in
                    state = .failed
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: 54, height: 54)
        } else {
            // A homepage favicon can describe the host rather than the cask.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.gray)

                Text(fallbackInitial)
                    .font(.system(size: 24, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
        }
    }
}
