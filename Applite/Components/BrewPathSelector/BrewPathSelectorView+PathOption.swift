//
//  BrewPathSelectorView+PathOption.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension BrewPathSelectorView {
    func pathOption(_ option: BrewPaths.PathOption, showPath: Bool = true) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(getPathDescription(for: option))

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
}
