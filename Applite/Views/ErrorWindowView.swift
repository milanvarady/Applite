//
//  ErrorWindowView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 25..
//

import SwiftUI

struct ErrorWindowView: View {
    let errorString: String
    
    var body: some View {
        ScrollView {
            VStack {
                Text(errorString)
                    .textSelection(.enabled)
            }
            .padding()
        }
    }
}

#Preview {
    ErrorWindowView(errorString: "Error: This is just an example")
}
