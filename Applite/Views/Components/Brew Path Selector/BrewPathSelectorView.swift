//
//  BrewPathSelectorView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 03..
//

import SwiftUI
import DebouncedOnChange

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
        .onChange(of: brewPathOption) { _ in
            Task { @MainActor in
                isSelectedPathValid = await BrewPaths.isSelectedBrewPathValid()
            }
        }
        .onChange(of: customUserBrewPath, debounceTime: .seconds(0.5)) { newPath in
            customUserBrewPath = newPath

            if brewPathOption == BrewPaths.PathOption.custom.rawValue {
                Task { @MainActor in
                    isSelectedPathValid = await BrewPaths.isBrewPathValid(at: URL(fileURLWithPath: newPath))
                }
            }
        }
    }
}

struct BrewPathSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        BrewPathSelectorView(isSelectedPathValid: .constant(false))
    }
}
