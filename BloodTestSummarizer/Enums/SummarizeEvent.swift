//
//  SummarizeEvent.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import Foundation

/// A progress or terminal event emitted while streaming a summary from Claude.
enum SummarizeEvent: Sendable {
    case progress(phase: SummarizePhase, testsFound: Int)
    case finished(BloodTestSummary)
}
