//
//  UpdateView+UpdateUnavailable.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension UpdateView {
    var updateUnavailable: some View {
        VStack {
            Spacer()

            Text("No Updates Available")
                .font(.title)

            Spacer()
        }
    }
}
