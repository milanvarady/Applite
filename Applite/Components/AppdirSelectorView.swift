//
//  AppdirSelectorView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 25..
//

import SwiftUI

struct AppdirSelectorView: View {
    @AppStorage(Preferences.appdirOn.rawValue) var appdirOn = false
    @AppStorage(Preferences.appdirPath.rawValue) var appdirPath = "/Applications"
    
    @State var choosingAppdir = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Use Custom Installation Directory", isOn: $appdirOn)
            
            HStack {
                TextField("Custom Installation Directory", text: $appdirPath, prompt: Text("/path/to/dir"))
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                
                Button("Select Folder") {
                    choosingAppdir = true
                }
                .fileImporter(
                    isPresented: $choosingAppdir,
                    allowedContentTypes: [.directory]
                ) { result in
                    switch result {
                    case .success(let file):
                        appdirPath = file.path
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }
            .disabled(!appdirOn)
        }
    }
}

#Preview {
    AppdirSelectorView()
}
