//
//  PlaceholderAppView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 12. 21..
//

import SwiftUI

/// A placeholder app view shown while the apps are being loaded in
struct PlaceholderAppView: View {
    var body: some View {
        HStack {
            PlaceholderAppIcon()
                .padding(.leading)
            
            VStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray)
                    .frame(width: 140, height: 10)
                    .padding(.bottom, 2)
                
                Rectangle()
                    .fill(.gray)
                    .frame(width: 180, height: 3)
                
                Rectangle()
                    .fill(.gray)
                    .frame(width: 160, height: 3)
            }
            
            Spacer()
        }
    }
}

/// A placeholder app icon if loading from the API fails
public struct PlaceholderAppIcon: View {
    public var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(.gray, lineWidth: 3)
            .frame(width: 44, height: 44)
    }
}

struct PlaceholderAppView_Previews: PreviewProvider {
    static var previews: some View {
        PlaceholderAppView()
            .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)
    }
}
