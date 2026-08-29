import Foundation

/// Reads the Anthropic API key for LOCAL PROTOTYPING ONLY.
///
/// Do not hardcode a real key in source. This reads from an Info.plist
/// entry (`ANTHROPIC_API_KEY`) that you inject via a local .xcconfig file
/// excluded from version control — see README.md "Getting it running".
///
/// This entire type goes away once the app talks to your own backend
/// instead of api.anthropic.com directly.
enum APIConfiguration {
    static var apiKey: String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String,
            !value.isEmpty,
            value != "$(ANTHROPIC_API_KEY)" // unexpanded placeholder if the xcconfig wasn't picked up
        else { return nil }
        return value
    }
}
