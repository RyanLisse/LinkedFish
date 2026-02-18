// LinkedInKit - Swift library for LinkedIn scraping
//
// Provides programmatic access to LinkedIn data including:
// - Person profiles
// - Company profiles
// - Job search and details
// - Connection requests and messaging (via TinyFish)

@_exported import Foundation

/// LinkedInKit version
public let version = "2.0.0"

/// Create a configured TinyFish-backed LinkedIn client.
///
/// - Parameters:
///   - apiKey: Your TinyFish API key.
///   - liAtCookie: Optional LinkedIn `li_at` session cookie. Can be configured
///     later by calling `client.configure(liAtCookie:)` inside an async context.
/// - Returns: A ready-to-use `TinyFishClient`.
public func createTinyFishClient(apiKey: String, liAtCookie: String? = nil) -> TinyFishClient {
    let client = TinyFishClient(apiKey: apiKey)
    // Cookie configuration is an actor-isolated async call; callers must
    // invoke `await client.configure(liAtCookie:)` separately when needed.
    return client
}

/// Create a LinkedInClient backed by TinyFish.
///
/// Loads the TinyFish API key from Keychain (or the `TINYFISH_API_KEY`
/// environment variable as a fallback). Throws if no API key is found.
///
/// - Parameter cookie: Optional LinkedIn `li_at` session cookie.
/// - Returns: A configured `LinkedInClient`.
/// - Throws: `CredentialError` if no API key is available.
///
/// > Note: Requires the TinyFish-backed `LinkedInClient` (Task #2 facade).
public func createClient(cookie: String? = nil) async -> LinkedInClient {
    let client = LinkedInClient()
    if let cookie = cookie {
        await client.configure(cookie: cookie)
    }
    return client
}

/// Helper to extract username from LinkedIn profile URL
public func extractUsername(from url: String) -> String? {
    // Handle various LinkedIn URL formats
    let patterns = [
        #"linkedin\.com/in/([a-zA-Z0-9\-_]+)"#,
        #"^([a-zA-Z0-9\-_]+)$"#, // Just the username
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: url) {
                return String(url[captureRange])
            }
        }
    }
    
    return nil
}

/// Helper to extract company name from LinkedIn company URL
public func extractCompanyName(from url: String) -> String? {
    let patterns = [
        #"linkedin\.com/company/([a-zA-Z0-9\-_]+)"#,
        #"^([a-zA-Z0-9\-_]+)$"#, // Just the company name
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: url) {
                return String(url[captureRange])
            }
        }
    }
    
    return nil
}

/// Helper to extract job ID from LinkedIn job URL
public func extractJobId(from url: String) -> String? {
    let patterns = [
        #"linkedin\.com/jobs/view/(\d+)"#,
        #"^(\d+)$"#, // Just the job ID
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: url) {
                return String(url[captureRange])
            }
        }
    }
    
    return nil
}
