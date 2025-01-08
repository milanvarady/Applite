//
//  AppMigrationView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.30.
//

import SwiftUI

struct AppMigrationView: View {
    let width: CGFloat = 620
    let cardPadding: CGFloat = 24

    var body: some View {
        ScrollView {
            VStack {
                titleAndDescription
                    .padding(.vertical, 40)
                
                HStack(spacing: 40) {
                    Card(paddig: cardPadding) {
                        ExportView()
                    }
                    
                    Card(paddig: cardPadding) {
                        ImportView()
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: width)
        }
    }

    var titleAndDescription: some View {
        VStack(alignment: .leading) {
            Text("App Migration", comment: "App Migration view title")
                .font(.appliteMediumTitle)
                .padding(.bottom, 2)

            Text(
                "Export all of your currently installed apps to a file. Import the file to another device to install them all. Useful when setting up a new Mac.",
                comment: "App migration view description"
            )
        }
    }
}

#Preview {
    AppMigrationView()
        .padding()
}
