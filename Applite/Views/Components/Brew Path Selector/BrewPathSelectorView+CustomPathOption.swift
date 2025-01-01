//
//  BrewPathSelectorView+CustomPathOption.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension BrewPathSelectorView {
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
}
