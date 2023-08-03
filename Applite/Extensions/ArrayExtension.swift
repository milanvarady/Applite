//
//  ArrayExtension.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 31..
//

import Foundation

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
