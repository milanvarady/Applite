//
//  FuzzySearch.swift
//  Applite
//
//  Created by Milán Várady on 2025.
//

import Foundation

/// A weighted search property for fuzzy matching
struct FuzzySearchProperty: Sendable {
    let text: String
    let weight: Double

    init(_ text: String, weight: Double = 1.0) {
        self.text = text
        self.weight = weight
    }
}

/// Protocol for types that can be fuzzy searched
protocol FuzzySearchable {
    var searchProperties: [FuzzySearchProperty] { get }
}

/// Result of a fuzzy search operation
struct FuzzySearchResult {
    let index: Int
    let score: Double
}

/// Performs fuzzy search on a collection of items
enum FuzzySearch {
    /// Search for a query in a collection, returning results sorted by score (lower is better match)
    static func search<T>(
        _ query: String,
        in items: [T],
        by keyPath: KeyPath<T, [FuzzySearchProperty]>
    ) async -> [FuzzySearchResult] {
        let lowercasedQuery = query.lowercased()

        var results: [FuzzySearchResult] = []

        for (index, item) in items.enumerated() {
            let properties = item[keyPath: keyPath]
            var bestScore = Double.infinity

            for property in properties {
                let text = property.text.lowercased()
                let weight = property.weight
                let score = computeScore(query: lowercasedQuery, text: text)

                if score < Double.infinity {
                    let weightedScore = score / weight
                    bestScore = min(bestScore, weightedScore)
                }
            }

            if bestScore < Double.infinity {
                results.append(FuzzySearchResult(index: index, score: bestScore))
            }
        }

        results.sort { $0.score < $1.score }
        return results
    }

    /// Compute a fuzzy match score between query and text.
    /// Returns Double.infinity for no match. Lower scores = better match.
    /// Score is normalized to 0...1 range for matches.
    private static func computeScore(query: String, text: String) -> Double {
        if query.isEmpty { return 0 }
        if text.isEmpty { return .infinity }

        // Exact match
        if text == query { return 0 }

        // Prefix match
        if text.hasPrefix(query) {
            return 0.01
        }

        // Contains as substring
        if text.contains(query) {
            return 0.05
        }

        // Fuzzy character-by-character matching
        let queryChars = Array(query)
        let textChars = Array(text)

        var queryIndex = 0
        var lastMatchIndex = -1
        var totalGap = 0
        var consecutiveMatches = 0
        var maxConsecutive = 0

        for (textIndex, textChar) in textChars.enumerated() {
            guard queryIndex < queryChars.count else { break }

            if textChar == queryChars[queryIndex] {
                if lastMatchIndex >= 0 {
                    let gap = textIndex - lastMatchIndex - 1
                    totalGap += gap
                    if gap == 0 {
                        consecutiveMatches += 1
                        maxConsecutive = max(maxConsecutive, consecutiveMatches)
                    } else {
                        consecutiveMatches = 0
                    }
                }
                lastMatchIndex = textIndex
                queryIndex += 1
            }
        }

        // Not all query characters found
        guard queryIndex == queryChars.count else {
            return .infinity
        }

        // Compute score: penalize gaps, reward consecutive matches
        let gapPenalty = Double(totalGap) / Double(textChars.count)
        let consecutiveBonus = Double(maxConsecutive) / Double(queryChars.count)
        let lengthPenalty = Double(textChars.count - queryChars.count) / Double(textChars.count)

        let score = 0.1 + gapPenalty * 0.4 + lengthPenalty * 0.3 - consecutiveBonus * 0.2
        return min(max(score, 0.06), 1.0)
    }
}
