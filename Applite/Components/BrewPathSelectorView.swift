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
    
    @AppStorage("customUserBrewPath") var customUserBrewPath: String = BrewPaths.getBrewExectuablePath(for: .defaultAppleSilicon, shellFriendly: false)
    @AppStorage("brewPathOption") var brewPathOption = BrewPaths.PathOption.defaultAppleSilicon.rawValue
    
    private func getPathDesctiption(for option: BrewPaths.PathOption) -> String {
        switch option {
        case .appPath:
            return "\(Bundle.main.appName)'s installation"
            
        case .defaultAppleSilicon:
            return "Apple Silicon mac"
            
        case .defaultIntel:
            return "Intel mac"
            
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
                            Text("\(BrewPaths.getBrewExectuablePath(for: option, shellFriendly: false)) **(\(getPathDesctiption(for: option)))**")
                                .truncationMode(.middle)
                            
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
                            
                            TextField("Custom brew path", text: $customBrewPathDebounced.text, prompt: Text("/path/to/brew"))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)
                                .autocorrectionDisabled()
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
