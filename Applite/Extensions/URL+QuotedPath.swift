//
//  URLExtension.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 30..
//

import Foundation

extension URL {
    func quotedPath() -> String {
        return "\"\(self.path(percentEncoded: false))\""
    }
}
