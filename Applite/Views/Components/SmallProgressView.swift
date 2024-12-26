//
//  SmallProgressView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 09..
//

import SwiftUI

/// A regual `ProgressView` with a scale effect of 0.8
struct SmallProgressView: View {
    var body: some View {
        ProgressView()
            .scaleEffect(0.8)
    }
}

struct SmallProgressView_Previews: PreviewProvider {
    static var previews: some View {
        SmallProgressView()
    }
}
