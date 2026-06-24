//
//  CaskProgressState.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

/// Cask progress state when installing, updating or uninstalling
enum CaskProgressState: Equatable, Hashable {
    case idle
    case busy(withTask: String)
    case downloading(percent: Double)
    case success
    case failed(output: String)
}
