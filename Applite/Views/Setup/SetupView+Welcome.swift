//
//  SetupView+Welcome.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SetupView {
    /// Welcome page
    struct Welcome: View {
        var body: some View {
            VStack {
                Text("Welcome to \(Bundle.main.appName)")
                    .font(.system(size: 36, weight: .bold))
                    .padding(.top, 50)
                    .padding(.bottom, 25)

                VStack(alignment: .leading, spacing: 16) {
                    Feature(sfSymbol: "square.and.arrow.down.on.square",
                            title: "Download apps with ease",
                            description: "Download third party applications with a single click. No more \"Drag to Applications folder\".")

                    Feature(sfSymbol: "cursorarrow.and.square.on.square.dashed",
                            title: "Manage applications",
                            description: "Update and uninstall your applications. No more leftover files from deleted applications.")

                    Feature(sfSymbol: "sparkle.magnifyingglass",
                            title: "Discover",
                            description: "Browse through a handpicked list of awesome apps.")
                }
            }
            .frame(maxWidth: 500)
        }

        /// A feature of the app to be displayed in the Welcome view
        private struct Feature: View {
            let sfSymbol: String
            let title: LocalizedStringKey
            let description: LocalizedStringKey

            var body: some View {
                HStack {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 22))
                        .padding(.trailing, 5)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text(title, comment: "Title")
                            .font(.system(size: 14, weight: .bold))

                        Text(description, comment: "Description")
                            .font(.system(size: 12, weight: .light))
                    }
                }
            }
        }
    }
}
