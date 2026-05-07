//
//  CategoryLoadResult+LocalizedName
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import SwiftUI

extension CategoryLoadResult {
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(self.id)
    }

    var name: String { id }

    /// Casks grouped in pairs for the discover section scroll view
    var casksCoupled: [[CaskViewModel]] {
        stride(from: 0, to: casks.count, by: 2).map { i in
            Array(casks[i..<min(i + 2, casks.count)])
        }
    }
}
