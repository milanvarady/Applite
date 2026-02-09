//
//  SearchableCaskCollection.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import Foundation

@MainActor
class SearchableCaskCollection: ObservableObject {
    @Published private(set) var casks: [Cask] = []
    @Published private(set) var casksMatchingSearch: [Cask] = []

    init(casks: [Cask] = []) {
        self.defineCasks(casks)
    }

    func defineCasks(_ casks: [Cask]) {
        self.casks = casks
        self.casksMatchingSearch = casks
    }

    func addCask(_ cask: Cask) {
        self.casks.append(cask)
    }

    func remove(_ cask: Cask) {
        self.casks.removeAll(where: { $0 == cask })
        self.casksMatchingSearch.removeAll(where: { $0 == cask })
    }

    func removeAll() {
        self.casks.removeAll()
        self.casksMatchingSearch.removeAll()
    }

    func search(query: String, diffScroreThreshold: Double = 0.2, limitResults: Int = 20) async {
        guard !query.isEmpty else {
            self.casksMatchingSearch = self.casks
            return
        }

        let searchResults = await FuzzySearch.search(query, in: self.casks, by: \Cask.searchProperties)

        var matchedCasks: [Cask] = []

        for result in searchResults {
            guard result.score <= diffScroreThreshold else {
                break
            }

            guard matchedCasks.count <= limitResults else {
                break
            }

            if let match = self.casks[safeIndex: result.index] {
                matchedCasks.append(match)
            }
        }

        self.casksMatchingSearch = matchedCasks
    }

    func filterSearch(by filter: ([Cask]) -> [Cask]) {
        self.casksMatchingSearch = filter(casksMatchingSearch)
    }

    func setReserveCapacity(_ capacity: Int) {
        self.casks.reserveCapacity(capacity)
        self.casksMatchingSearch.reserveCapacity(capacity)
    }
}
