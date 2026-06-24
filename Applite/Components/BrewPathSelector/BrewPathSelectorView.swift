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

    func pathOption(_ option: BrewPaths.PathOption, showPath: Bool = true) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(getPathDescription(for: option))

                if option.rawValue == brewPathOption {
                    Image(systemName: isSelectedPathValid ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelectedPathValid ? .green : .red)
                }
            }

            if showPath {
                Text(BrewPaths.getBrewExectuablePath(for: option).path(percentEncoded: false))
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .fontWeight(.thin)
                    .fontDesign(.monospaced)
            }
        }
    }

    func customPathOption(option: BrewPaths.PathOption) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            pathOption(option, showPath: false)

            HStack {
                TextField("Custom brew path", text: $customUserBrewPath, prompt: Text("/path/to/brew"))
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
                        customUserBrewPath = file.path(percentEncoded: false)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }
            .disabled(brewPathOption != BrewPaths.PathOption.custom.rawValue)
        }
    }

    func getPathDescription(for option: BrewPaths.PathOption) -> LocalizedStringKey {
        switch option {
        case .appPath:
            return "Applite's installation"

        case .defaultAppleSilicon:
            return "Apple Silicon Mac"

        case .defaultIntel:
            return "Intel Mac"

        case .custom:
            return "Custom"
        }
    }
}

#Preview {
    BrewPathSelectorView(isSelectedPathValid: .constant(false))
}
