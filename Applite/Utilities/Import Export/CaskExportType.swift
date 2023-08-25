//
//  CaskExportType.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 20..
//

import Foundation

enum CaskExportType: String, CaseIterable, Identifiable {
    var id: Self { self }
    
    case txtFile = "Cask list (.txt file)"
    case brewfile = "Brewfile"
}
