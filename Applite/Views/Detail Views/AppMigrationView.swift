//
//  AppMigrationView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.30.
//

import SwiftUI

struct AppMigrationView: View {
    let width: CGFloat = 620
    let columnSpacing: CGFloat = 40

    var cardWidth: CGFloat {
        (width - columnSpacing) / 2
    }
    let cardHeight: CGFloat = 210
    let cardPadding: CGFloat = 28

    var body: some View {
        VStack {
            titleAndDescription
                .padding(.vertical, 40)

            HStack(spacing: columnSpacing) {
                Card(cardWidth: cardWidth, cardHeight: cardHeight, paddig: cardPadding) {
                    ExportView()
                }

                Card(cardWidth: cardWidth, cardHeight: cardHeight, paddig: cardPadding) {
                    ImportView()
                }
            }

            Spacer()
        }
        .frame(maxWidth: width)
    }

    var titleAndDescription: some View {
        VStack(alignment: .leading) {
            Text("App Migration")
                .font(.appliteMediumTitle)
                .padding(.bottom, 2)

            Text("Export all of your currently installed apps to a file. Import the file to another device to install them all. Useful when setting up a new Mac.")
        }
    }

    private struct ExportView: View {
        @State var selectedExportFileType: CaskExportType = .txtFile

        var body: some View {
            VStack(alignment: .leading) {
                Text("Export")
                    .font(.appliteSmallTitle)

                Button {
                    
                } label: {
                    Label("Export Apps to File", systemImage: "square.and.arrow.up")
                }
                .controlSize(.large)
                .padding(.bottom, 2)

                Picker("Export file type", selection: $selectedExportFileType) {
                    ForEach(CaskExportType.allCases) { type in
                        Text(LocalizedStringKey(type.rawValue))
                    }
                }

                Spacer()
            }
        }
    }

    private struct ImportView: View {
        var body: some View {
            VStack(alignment: .leading) {
                Text("Import")
                    .font(.appliteSmallTitle)

                Button {

                } label: {
                    Label("Import Apps", systemImage: "square.and.arrow.down")
                }
                .controlSize(.large)
                .padding(.bottom, 4)

                Text("**Note:** When importing a Brewfile only casks will be installed. Other items like formulae and taps will be skipped.")

                Spacer()
            }
        }
    }
}

#Preview {
    AppMigrationView()
}
