//
//  URL+ChecksumInBase64.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation
import CryptoKit

extension URL {
    func checksumInBase64() -> String? {
        let bufferSize = 16*1024

        do {
            // Open file for reading:
            let file = try FileHandle(forReadingFrom: self)
            defer {
                file.closeFile()
            }

            // Create and initialize MD5 context:
            var md5 = CryptoKit.Insecure.MD5()

            // Read up to `bufferSize` bytes, until EOF is reached, and update MD5 context:
            while autoreleasepool(invoking: {
                let data = file.readData(ofLength: bufferSize)
                if data.count > 0 {
                    md5.update(data: data)
                    return true // Continue
                } else {
                    return false // End of file
                }
            }) { }

            // Compute the MD5 digest:
            let data = Data(md5.finalize())

            return data.base64EncodedString()
        } catch {
            return nil
        }
    }
}
