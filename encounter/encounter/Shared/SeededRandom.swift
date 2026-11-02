//
//  SeededRandom.swift
//  encounter
//

import Foundation

/// A random source that gives the same run of numbers for the same seed, so a generated map can be made again.
/// (SplitMix64: small, quick, and good enough for scattering buildings.)
nonisolated struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// A number from `range`, as a fraction of the way through it.
    mutating func value(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }

    /// True with the given chance, 0 to 1.
    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &self) < probability }

    /// One of the choices, or the first if the weights are all zero.
    mutating func pick<T>(_ choices: [(T, Double)]) -> T {
        let total = choices.reduce(0) { $0 + max($1.1, 0) }
        guard total > 0 else { return choices[0].0 }
        var roll = Double.random(in: 0..<total, using: &self)
        for (choice, weight) in choices {
            roll -= max(weight, 0)
            if roll < 0 { return choice }
        }
        return choices[choices.count - 1].0
    }
}
