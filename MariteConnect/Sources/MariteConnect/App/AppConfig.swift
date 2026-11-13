import Foundation

/// Central place for app-wide configuration. Fill these in per docs/SETUP.md.
///
/// Unlike a typical backend-based app, `claudeAPIKey` genuinely is a secret
/// that ends up inside the shipped app binary — there is no server here to
/// hide it behind (that's the deliberate tradeoff of this architecture: no
/// backend to run, at the cost of the key being extractable by anyone who
/// gets the app's binary). That's an acceptable risk for an app you build,
/// sign, and hand only to Marite staff — never submit a build with a real
/// key to the public App Store. Mitigate the downside by setting a monthly
/// spending limit on the key at console.anthropic.com.
enum AppConfig {
    /// From console.anthropic.com → API Keys. Set a spending limit on this key.
    static let claudeAPIKey = "REPLACE_WITH_YOUR_ANTHROPIC_API_KEY"
    static let claudeModel = "claude-sonnet-5"

    /// Must match the iCloud container identifier in both the entitlements
    /// file and your Apple Developer / CloudKit Dashboard setup. See docs/SETUP.md.
    static let cloudKitContainerIdentifier = "iCloud.com.marite.MariteConnect"
}
