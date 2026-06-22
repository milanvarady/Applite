//
//  BrewPathSelectorView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 03..
//

import SwiftUI

/// Provides a picker so the user can select the brew executable path they want to use
struct BrewPathSelectorView: View {
    @Binding var isSelectedPathValid: Bool

    @AppStorage(Preferences.customUserBrewPath.rawValue) var customUserBrewPath: String = BrewPaths.getBrewExectuablePath(for: .defaultAppleSilicon).path(percentEncoded: false)
    @AppStorage(Preferences.brewPathOption.rawValue) var brewPathOption = BrewPaths.PathOption.defaultAppleSilicon.rawValue

    @State var choosingCustomFolder = false

    var body: some View {
        VStack(alignment: .leading) {
            Picker("", selection: $brewPathOption) {
                ForEach(BrewPaths.PathOption.allCases) { option in
                    if option != .custom {
                        pathOption(option)
                            .tag(option.rawValue)
                    } else {
                        customPathOption(option: option)
                            .tag(option.rawValue)
                    }
                }
            }
            .pickerStyle(.radioGroup)
        }
        .task {
            isSelectedPathValid = await BrewPaths.isSelectedBrewPathValid()
        }
        .onChange(of: brewPathOption) {
            Task { @MainActor in
                isSelectedPathValid = await BrewPaths.isSelectedBrewPathValid()
            }
        }
        .task(id: customUserBrewPath) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard brewPathOption == BrewPaths.PathOption.custom.rawValue else { return }
            isSelectedPathValid = await BrewPaths.isBrewPathValid(at: URL(fileURLWithPath: customUserBrewPath))
        }
    }
}

struct BrewPathSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        BrewPathSelectorView(isSelectedPathValid: .constant(false))
    }
}
