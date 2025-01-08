//
//  BrewPathSelectorView+PathOption.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension BrewPathSelectorView {
    func pathOption(_ option: BrewPaths.PathOption, showPath: Bool = true) -> some View {
        HStack {
            Text(getPathDescription(for: option))

            if showPath {
                Text("(\(BrewPaths.getBrewExectuablePath(for: option, shellFriendly: false)))")
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .foregroundColor(.gray)
            }

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
    }
}
