//
//  DebounceObject.swift
//  Applite
//
//  Created by Milán Várady on 2022. 12. 30..
//

import Foundation
import Combine

/// Debounces a changing `String` and only publishes it when it stops changing for a predetermined time. Used in text fields.
///
/// Got this from https://onmyway133.com/posts/how-to-debounce-textfield-search-in-swiftui/
final public class DebounceObject: ObservableObject {
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    private var bag = Set<AnyCancellable>()

    public init(dueTime: TimeInterval = 0.5) {
        $text
            .removeDuplicates()
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &bag)
    }
}
