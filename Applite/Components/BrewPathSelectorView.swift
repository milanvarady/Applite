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

    @StateObject var customBrewPathDebounced = DebounceObject()

    @AppStorage(Preferences.customUserBrewPath.rawValue) var customUserBrewPath: String = BrewPaths.getBrewExectuablePath(for: .defaultAppleSilicon, shellFriendly: false)
    @AppStorage(Preferences.brewPathOption.rawValue) var brewPathOption = BrewPaths.PathOption.defaultAppleSilicon.rawValue
    
    @State var choosingCustomFolder = false

    private func getPathDescription(for option: BrewPaths.PathOption) -> String {
        switch option {
        case .appPath:
            return "\(Bundle.main.appName)'s installation"

        case .defaultAppleSilicon:
            return "Apple Silicon Mac"

        case .defaultIntel:
            return "Intel Mac"

        case .custom:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker("", selection: $brewPathOption) {
                ForEach(BrewPaths.PathOption.allCases) { option in
                    if option != .custom {
                        HStack {
                            Text("\(getPathDescription(for: option))")
                            Text("(\(BrewPaths.getBrewExectuablePath(for: option, shellFriendly: false)))").truncationMode(.middle).lineLimit(1).foregroundColor(.gray)
                            if option.rawValue == brewPathOption {
                                if isSelectedPathValid {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .tag(option.rawValue)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Custom")

                                if option.rawValue == brewPathOption {
                                    if isSelectedPathValid {
                                        Image(systemName: "checkmark.circle")
                                            .font(.system(size: 16))
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 16))
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            
                            HStack {
                                TextField("Custom brew path", text: $customBrewPathDebounced.text, prompt: Text("/path/to/brew"))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 300)
                                    .autocorrectionDisabled()
                                
                                Button("Browse") {
                                    choosingCustomFolder = true
                                }
                                .fileImporter(
                                    isPresented: $choosingCustomFolder,
                                    allowedContentTypes: [.unixExecutable]
                                ) { result in
                                    switch result {
                                    case .success(let file):
                                        customBrewPathDebounced.text = file.path
                                    case .failure(let error):
                                        print(error.localizedDescription)
                                    }
                                }
                            }
                            .disabled(brewPathOption != BrewPaths.PathOption.custom.rawValue)
                        }
                        .tag(option.rawValue)
                    }
                }
            }
            .pickerStyle(.radioGroup)
        }
        .onAppear {
            customBrewPathDebounced.text = customUserBrewPath
            isSelectedPathValid = BrewPaths.isSelectedBrewPathValid()
        }
        .onChange(of: brewPathOption) { _ in
            isSelectedPathValid = BrewPaths.isSelectedBrewPathValid()
        }
        .onChange(of: customBrewPathDebounced.debouncedText) { newPath in
            customUserBrewPath = newPath

            if brewPathOption == BrewPaths.PathOption.custom.rawValue {
                isSelectedPathValid = isBrewPathValid(path: newPath)
            }
        }
    }
}

struct BrewPathSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        BrewPathSelectorView(isSelectedPathValid: .constant(false))
    }
}
