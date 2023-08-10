//
//  UninstallSelfView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 14..
//

import SwiftUI

/// Uninstalls Applite and related files
struct UninstallSelfView: View {
    @State var deleteBrewCache = false
    @State var showConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Uninstall \(Bundle.main.appName)")
                .font(.system(size: 26, weight: .bold))
                .padding(.bottom)
            
            Text("This will uninstall all files and cache associated with \(Bundle.main.appName).")
            
            Toggle("Delete Homebrew cache", isOn: $deleteBrewCache)
            
            Text("**Warning**: Homebrew cache is shared between Homebrew installations. Deleting the cache will remove the cache for all installations!")
            
            Divider()
                .padding(.vertical)
            
            Button {
                showConfirmation = true
            } label: {
                Label("Uninstall \(Bundle.main.appName)", systemImage: "trash.fill")
            }
            .bigButton(foregroundColor: .white, backgroundColor: .red)
            
            Spacer()
        }
        .frame(width: 400, height: 250)
        .confirmationDialog("Are you sure you want to permanently uninstall \(Bundle.main.appName)?", isPresented: $showConfirmation) {
            Button("Uninstall", role: .destructive) {
                uninstallSelf(deleteBrewCache: deleteBrewCache)
         
            }
            
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct UninstallSelfView_Previews: PreviewProvider {
    static var previews: some View {
        UninstallSelfView()
    }
}
