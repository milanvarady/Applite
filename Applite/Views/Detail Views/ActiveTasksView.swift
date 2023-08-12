//
//  ActiveTasksView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 12..
//

import SwiftUI

struct ActiveTasksView: View {
    @EnvironmentObject var caskData: CaskData
    
    var body: some View {
        VStack {
            if caskData.busyCasks.isEmpty {
                Text("No Active Tasks")
                    .font(.title)
            } else {
                AppGridView(casks: Array(caskData.busyCasks), appRole: .update)
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ActiveTasksView()
}
