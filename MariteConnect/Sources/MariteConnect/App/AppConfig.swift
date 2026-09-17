import Foundation

/// Central place for tenant-specific configuration.
/// Fill these in per docs/SETUP.md before building. None of these values are secret
/// (the MSAL client ID and tenant ID are public identifiers), so they're safe to
/// commit — actual secrets (Anthropic API key, Function keys) live only in the
/// serverless backend, never in the app.
enum AppConfig {
    /// Application (client) ID from the Entra ID app registration.
    static let msalClientId = "REPLACE_WITH_ENTRA_APP_CLIENT_ID"

    /// Directory (tenant) ID, or "organizations" if you want any work account to sign in.
    static let msalTenantId = "REPLACE_WITH_ENTRA_TENANT_ID"

    static var msalAuthority: String {
        "https://login.microsoftonline.com/\(msalTenantId)"
    }

    /// Must match the URL scheme registered in project.yml / Info.plist and in the
    /// Entra ID app registration's iOS platform redirect URI.
    static let msalRedirectUri = "msauth.com.marite.MariteConnect://auth"

    /// Delegated Microsoft Graph scopes the app requests at sign-in.
    static let graphScopes: [String] = [
        "User.Read",
        "Team.ReadBasic.All",
        "Channel.ReadBasic.All",
        "ChannelMessage.Send",
        "ChannelMessage.Read.All",
        "Sites.ReadWrite.All",
        "Files.ReadWrite.All"
    ]

    static let graphBaseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    /// The Microsoft Team that backs Marite Connect's channels. Create a dedicated
    /// Team (e.g. "Marite Staff") so channel membership maps cleanly to app access:
    /// standard channels = visible to all staff, private channels = visible only to
    /// the members you add. See docs/SETUP.md.
    static let staffTeamId = "REPLACE_WITH_TEAM_ID"

    /// SharePoint site hosting the "StaffTasks" list and the legal document library.
    static let siteId = "REPLACE_WITH_SHAREPOINT_SITE_ID"
    static let staffTasksListName = "StaffTasks"
    static let legalLibraryDriveName = "Sectional Title Legal Library"

    /// Base URL of the deployed Azure Function relay for the legal assistant
    /// (see ServerlessBackend/legal-assistant-function).
    static let assistantEndpoint = URL(string: "https://REPLACE_WITH_YOUR_FUNCTION.azurewebsites.net/api/legalAssistant")!
}
