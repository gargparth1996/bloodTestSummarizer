import Foundation

/// The structured summary Claude returns for an uploaded blood test PDF.
///
/// This mirrors the JSON schema we ask for in `ClaudeAPIService.systemPrompt`.
/// If you change one, change the other.
struct BloodTestSummary: Codable, Sendable {
    let overallImpression: String
    let findings: [Finding]
    let recommendations: [String]
    let disclaimer: String

    struct Finding: Codable, Sendable {
        let testName: String
        let value: String
        let unit: String
        let referenceRange: String
        let flag: Flag

        enum Flag: String, Codable, Sendable {
            case normal
            case low
            case high
            case critical
        }
    }
}
