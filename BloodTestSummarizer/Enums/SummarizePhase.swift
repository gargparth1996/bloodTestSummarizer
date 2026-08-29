//
//  SummarizePhase.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import Foundation

/// Coarse phase of the streamed response, inferred from the JSON keys seen
/// so far in the accumulated text (not a fixed timer) — real signal, not a
/// simulation.
enum SummarizePhase: Sendable, Equatable {
    case uploading
    case analyzing
    case extractingFindings
    case buildingRecommendations
    case finalizing
}
