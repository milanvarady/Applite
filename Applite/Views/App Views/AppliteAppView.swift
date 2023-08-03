//
//  AppliteAppView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 29..
//

import SwiftUI

/// This view is included in the installed section so users can update and uninstall Applite itself
struct AppliteAppView: View {
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        HStack {
            Image("AppliteIcon")
                .resizable()
                .frame(width: 54, height: 54)
                .padding(.leading, 5)
            
            // Name and description
            VStack(alignment: .leading) {
                Text("Applite")
                    .font(.system(size: 16, weight: .bold))
                
                Text("This app")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                
            } label: {
                Label("Update", systemImage: "arrow.uturn.down")
                    .foregroundColor(.blue)
            }
            .clipShape(Capsule())
            
            Button {
                openWindow(id: "uninstall-self")
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
        .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)
    }
}

struct AppliteAppView_Previews: PreviewProvider {
    static var previews: some View {
        AppliteAppView()
    }
}
