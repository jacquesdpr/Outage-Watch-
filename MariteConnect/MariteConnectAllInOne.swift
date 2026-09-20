// MariteConnectAllInOne.swift
//
// The ENTIRE Marite Connect app in one file, meant to be pasted into a single
// new Swift file in Xcode. This is the exact same code as the multi-file
// version in Sources/MariteConnect/ — just concatenated into one file for a
// quicker start. See PASTE_IN_XCODE.md in this same folder for the full,
// step-by-step setup (new project, adding the MSAL package, enabling Push
// Notifications, and editing Info.plist) — none of that can be pasted as
// code, it's done through Xcode's UI.
//
// Nothing in this file will do anything "real" (sign-in, chat, tasks,
// search, the legal assistant, or push notifications) until you fill in the
// placeholder values in the AppConfig enum below, and finish the Microsoft
// 365 / Entra ID / Azure setup described in docs/SETUP.md. Until then, the
// app builds and runs, and the sign-in screen will show an error when tapped
// — that's expected.

import Foundation
import SwiftUI
import UIKit
import MSAL
import UserNotifications

// MARK: - App/AppConfig.swift

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

    /// Must match the URL scheme registered in Info.plist and in the
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

    /// Base URL of the deployed Azure Function App backing the legal assistant
    /// and push notifications (see ServerlessBackend/marite-functions).
    static let functionsBaseURL = URL(string: "https://REPLACE_WITH_YOUR_FUNCTION.azurewebsites.net/api")!

    static var assistantEndpoint: URL { functionsBaseURL.appendingPathComponent("legalAssistant") }
    static var registerDeviceEndpoint: URL { functionsBaseURL.appendingPathComponent("registerDevice") }
    static var unregisterDeviceEndpoint: URL { functionsBaseURL.appendingPathComponent("unregisterDevice") }
    static var notifyTaggedEndpoint: URL { functionsBaseURL.appendingPathComponent("notifyTagged") }
}

// MARK: - Graph/GraphError.swift

enum GraphError: LocalizedError {
    case invalidResponse
    case http(status: Int, body: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .http(let status, let body):
            return "Microsoft Graph returned status \(status): \(body)"
        case .decoding(let error):
            return "Could not read the server's response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Models/ChannelModels.swift

/// Mirrors a Microsoft Teams channel. `membershipType` is what gives us the
/// "everyone" vs "certain people only" split for free: Teams standard channels are
/// visible to every team member, private channels only to the members explicitly
/// added to them.
struct Channel: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let description: String?
    let membershipType: MembershipType

    enum MembershipType: String, Codable {
        case standard
        case `private`
        case shared

        var isRestricted: Bool { self != .standard }
    }
}

struct ChannelListResponse: Decodable {
    let value: [Channel]
}

// MARK: - Models/MessageModels.swift

/// A message in a Teams channel, as returned by
/// GET /teams/{id}/channels/{id}/messages
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: String
    let createdDateTime: Date
    let from: MessageSender?
    let body: MessageBody
    let mentions: [ChatMention]

    var senderName: String { from?.user?.displayName ?? "Unknown" }
}

struct MessageSender: Codable, Hashable {
    let user: GraphUser?
}

struct GraphUser: Codable, Hashable {
    let id: String
    let displayName: String
    let userIdentityType: String?
}

struct MessageBody: Codable, Hashable {
    /// "html" or "text"
    let contentType: String
    let content: String
}

struct ChatMention: Codable, Hashable {
    let id: Int
    let mentionText: String
    let mentioned: MentionedIdentitySet
}

struct MentionedIdentitySet: Codable, Hashable {
    let user: GraphUser?
}

struct MessageListResponse: Decodable {
    let value: [ChatMessage]
}

/// Body used when posting a new message that @mentions one or more staff members.
/// Graph requires the mention markup (`<at id="0">Name</at>`) to appear inside the
/// HTML body, matched by index to the `mentions` array.
struct NewChatMessage: Encodable {
    let body: MessageBody
    let mentions: [ChatMention]?
}

enum MessageComposer {
    /// Builds the HTML body + mentions payload Graph expects for a message that
    /// tags one person and asks them to confirm completion.
    static func taskMessage(text: String, mentioning user: GraphUser) -> NewChatMessage {
        let html = "<at id=\"0\">\(user.displayName)</at> \(text.htmlEscaped)"
        let mention = ChatMention(id: 0, mentionText: user.displayName, mentioned: MentionedIdentitySet(user: user))
        return NewChatMessage(body: MessageBody(contentType: "html", content: html), mentions: [mention])
    }

    static func plainMessage(text: String) -> NewChatMessage {
        NewChatMessage(body: MessageBody(contentType: "text", content: text), mentions: nil)
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Models/TaskModels.swift

/// A staff task, backed by a row in the "StaffTasks" SharePoint list (see
/// docs/SETUP.md for the list schema). Created automatically whenever a channel
/// message @mentions someone, so every tag has a trackable, confirmable item.
struct StaffTask: Identifiable, Hashable {
    let itemId: String
    let channelId: String
    let messageId: String
    let channelName: String
    let summary: String
    let assignedToId: String
    let assignedToName: String
    let createdById: String
    let createdByName: String
    let createdDateTime: Date
    var status: Status

    var id: String { itemId }

    enum Status: String, Codable {
        case open = "Open"
        case done = "Done"
    }
}

// SharePoint list items come back as `{ id, fields: { ... } }`.
struct ListItemsResponse: Decodable {
    let value: [ListItem]
}

struct ListItem: Decodable {
    let id: String
    let createdDateTime: Date
    let fields: StaffTaskFields
}

struct StaffTaskFields: Codable {
    let Title: String              // task summary, shown in the list UI
    let ChannelId: String
    let ChannelName: String
    let MessageId: String
    let AssignedToId: String
    let AssignedToName: String
    let CreatedById: String
    let CreatedByName: String
    let Status: String
}

struct NewListItem<Fields: Encodable>: Encodable {
    let fields: Fields
}

extension StaffTask {
    init(itemId: String, fields: StaffTaskFields, createdDateTime: Date) {
        self.itemId = itemId
        self.channelId = fields.ChannelId
        self.messageId = fields.MessageId
        self.channelName = fields.ChannelName
        self.summary = fields.Title
        self.assignedToId = fields.AssignedToId
        self.assignedToName = fields.AssignedToName
        self.createdById = fields.CreatedById
        self.createdByName = fields.CreatedByName
        self.createdDateTime = createdDateTime
        self.status = StaffTask.Status(rawValue: fields.Status) ?? .open
    }
}

// MARK: - Models/SearchModels.swift

/// Result row shown in the SharePoint search tab, built from a Microsoft Graph
/// Search API (`/search/query`) hit.
struct SharePointSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let snippet: String
    let webUrl: String
    let lastModified: Date?
    let siteName: String?
}

// /search/query wire format (trimmed to the fields we use)

struct GraphSearchRequestBody: Encodable {
    let requests: [SearchRequestEntry]
}

struct SearchRequestEntry: Encodable {
    let entityTypes: [String]
    let query: SearchQuery
    let from: Int
    let size: Int
}

struct SearchQuery: Encodable {
    let queryString: String
}

struct GraphSearchResponse: Decodable {
    let value: [SearchResponseValue]
}

struct SearchResponseValue: Decodable {
    let hitsContainers: [HitsContainer]
}

struct HitsContainer: Decodable {
    let hits: [SearchHit]
}

struct SearchHit: Decodable {
    let hitId: String
    let summary: String?
    let resource: SearchResource
}

struct SearchResource: Decodable {
    let name: String?
    let webUrl: String?
    let lastModifiedDateTime: Date?
    let parentReference: SearchParentReference?
}

struct SearchParentReference: Decodable {
    let siteId: String?
}

extension SharePointSearchResult {
    init(hit: SearchHit) {
        self.id = hit.hitId
        self.title = hit.resource.name ?? "Untitled"
        self.snippet = hit.summary ?? ""
        self.webUrl = hit.resource.webUrl ?? ""
        self.lastModified = hit.resource.lastModifiedDateTime
        self.siteName = hit.resource.parentReference?.siteId
    }
}

// MARK: - Models/AssistantModels.swift

/// One turn in the Sectional Title Assistant conversation, shown as a chat bubble.
struct AssistantMessage: Identifiable, Hashable {
    let id = UUID()
    let role: Role
    let text: String
    var citations: [AssistantCitation] = []

    enum Role: String {
        case user
        case assistant
    }
}

/// A source document the assistant grounded its answer in — surfaced so staff can
/// open the actual Act clause or CSOS order rather than just trusting the summary.
struct AssistantCitation: Identifiable, Hashable {
    let id = UUID()
    let documentTitle: String
    let webUrl: String
    let excerpt: String
}

// Wire format for the Azure Function relay

struct AssistantRequestBody: Encodable {
    let question: String
    /// Recent turns, oldest first, so the relay can keep short conversational context.
    let history: [AssistantHistoryTurn]
}

struct AssistantHistoryTurn: Encodable {
    let role: String
    let text: String
}

struct AssistantResponseBody: Decodable {
    let answer: String
    let citations: [AssistantCitationWire]
}

struct AssistantCitationWire: Decodable {
    let documentTitle: String
    let webUrl: String
    let excerpt: String
}

// MARK: - Graph/GraphClient.swift

/// Thin async/await REST client for Microsoft Graph. Every call acquires a fresh
/// token from AuthManager (MSAL caches and silently refreshes it, so this is cheap).
final class GraphClient {
    private let authManager: AuthManager
    private let session: URLSession

    init(authManager: AuthManager, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await send(path: path, method: "GET", queryItems: queryItems, body: nil)
    }

    func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await send(path: path, method: "POST", queryItems: [], body: try JSONEncoder.graph.encode(body))
    }

    func patch<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "PATCH", queryItems: [], body: try JSONEncoder.graph.encode(body), allowEmptyBody: true)
    }

    /// Calls an absolute URL Graph itself returned (e.g. a `@odata.nextLink` or a
    /// `/search/query` POST target), rather than building the path ourselves.
    func postAbsolute<Body: Encodable, T: Decodable>(_ url: URL, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.graph.encode(body)
        return try await perform(request)
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Data?,
        allowEmptyBody: Bool = false
    ) async throws -> T {
        var components = URLComponents(url: AppConfig.graphBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw GraphError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await perform(request, allowEmptyBody: allowEmptyBody)
    }

    private func perform<T: Decodable>(_ request: URLRequest, allowEmptyBody: Bool = false) async throws -> T {
        var request = request
        let token = try await authManager.acquireToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GraphError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            throw GraphError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        if allowEmptyBody, data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try JSONDecoder.graph.decode(T.self, from: data)
        } catch {
            throw GraphError.decoding(error)
        }
    }
}

/// Used for PATCH/DELETE calls that return 204 No Content.
struct EmptyResponse: Decodable {}

extension JSONDecoder {
    static let graph: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let graph: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - Auth/AuthManager.swift

/// Wraps MSAL sign-in and silent token acquisition against Marite's Entra ID tenant.
/// This is the app's only source of Microsoft Graph access tokens.
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var displayName: String?
    @Published private(set) var email: String?
    @Published var lastError: String?

    private var application: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?

    init() {
        do {
            let config = MSALPublicClientApplicationConfig(
                clientId: AppConfig.msalClientId,
                redirectUri: AppConfig.msalRedirectUri,
                authority: try MSALAADAuthority(url: URL(string: AppConfig.msalAuthority)!)
            )
            application = try MSALPublicClientApplication(configuration: config)
            restoreExistingAccount()
        } catch {
            lastError = "Failed to configure sign-in: \(error.localizedDescription)"
        }
    }

    private func restoreExistingAccount() {
        guard let application else { return }
        do {
            if let account = try application.allAccounts().first {
                currentAccount = account
                isSignedIn = true
                displayName = account.username
                email = account.username
            }
        } catch {
            // No cached account yet; the user will need to sign in interactively.
        }
    }

    func signIn(presentingViewController: UIViewController) async {
        guard let application else { return }
        let webParameters = MSALWebviewParameters(authPresentationViewController: presentingViewController)
        let parameters = MSALInteractiveTokenParameters(scopes: AppConfig.graphScopes, webviewParameters: webParameters)

        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
                application.acquireToken(with: parameters) { result, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let result else {
                        continuation.resume(throwing: AuthError.noResult)
                        return
                    }
                    continuation.resume(returning: result)
                }
            }
            currentAccount = result.account
            isSignedIn = true
            displayName = result.account.username
            email = result.account.username
            lastError = nil
        } catch {
            lastError = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        guard let application, let currentAccount else { return }
        do {
            let params = MSALSignoutParameters()
            application.signout(with: currentAccount, signoutParameters: params) { [weak self] _, _ in
                Task { @MainActor in
                    self?.isSignedIn = false
                    self?.currentAccount = nil
                    self?.displayName = nil
                    self?.email = nil
                }
            }
        } catch {
            lastError = "Sign-out failed: \(error.localizedDescription)"
        }
    }

    /// Acquires a Graph access token silently, falling back to nil if interaction is
    /// required (the UI layer should then prompt for a fresh interactive sign-in).
    func acquireToken() async throws -> String {
        guard let application, let currentAccount else {
            throw AuthError.notSignedIn
        }
        let silentParameters = MSALSilentTokenParameters(scopes: AppConfig.graphScopes, account: currentAccount)
        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: silentParameters) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token = result?.accessToken else {
                    continuation.resume(throwing: AuthError.noResult)
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }

    enum AuthError: LocalizedError {
        case notSignedIn
        case noResult

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in."
            case .noResult: return "Sign-in did not return a result."
            }
        }
    }
}

// MARK: - Push/DeepLinkRouter.swift

/// Bridges a tapped push notification (handled in PushNotificationManager,
/// outside the SwiftUI view tree) to the channel list, which opens the right
/// channel once it sees a pending channel ID here. A shared singleton because
/// AppDelegate/UNUserNotificationCenterDelegate callbacks aren't part of the
/// SwiftUI environment.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingChannelId: String?

    private init() {}
}

// MARK: - Push/PushNotificationManager.swift

/// Requests notification permission, registers for APNs, and turns a tapped
/// "you've been tagged" notification into a deep link. A shared singleton
/// because APNs/UNUserNotificationCenter callbacks arrive through
/// AppDelegate, outside the SwiftUI view tree — views observe
/// `deviceToken` to know when to tell the backend about it.
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var deviceToken: String?

    private override init() {}

    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            // Permission can always be granted later from iOS Settings; nothing to do here.
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            self.deviceToken = hex
        }
    }

    func didFailToRegister(error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Show the alert even while the app is in the foreground, since a tagged
    /// task deserves attention whether or not you're already in the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let channelId = userInfo["channelId"] as? String else { return }
        await MainActor.run {
            DeepLinkRouter.shared.pendingChannelId = channelId
        }
    }
}

// MARK: - Push/AppDelegate.swift

/// SwiftUI's App protocol has no hook for APNs device token callbacks, so a
/// thin UIApplicationDelegate is still required — wired in via
/// @UIApplicationDelegateAdaptor in MariteConnectApp.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationManager.shared.didFailToRegister(error: error)
    }
}

// MARK: - Services/AppServices.swift

/// Wires up the Graph client and every feature service from a single shared
/// AuthManager, and caches the signed-in user's own Graph identity (needed to
/// stamp "createdBy" on tasks and to filter "my tasks").
@MainActor
final class AppServices: ObservableObject {
    let graph: GraphClient
    let chatService: ChatService
    let taskService: TaskService
    let searchService: SearchService
    let assistantService: AssistantService
    let pushNotificationService: PushNotificationService

    @Published private(set) var currentUser: GraphUser?

    init(authManager: AuthManager) {
        let graph = GraphClient(authManager: authManager)
        let taskService = TaskService(graph: graph)
        let pushNotificationService = PushNotificationService(authManager: authManager)
        self.graph = graph
        self.taskService = taskService
        self.pushNotificationService = pushNotificationService
        self.chatService = ChatService(graph: graph, taskService: taskService, pushNotificationService: pushNotificationService)
        self.searchService = SearchService(graph: graph)
        self.assistantService = AssistantService(authManager: authManager)
    }

    func loadCurrentUser() async {
        guard currentUser == nil else { return }
        currentUser = try? await graph.get("me", queryItems: [URLQueryItem(name: "$select", value: "id,displayName,userType")])
    }
}

// MARK: - Services/ChatService.swift

/// Reads and posts Teams channel messages, and automatically opens a StaffTask
/// whenever a new message @mentions someone.
final class ChatService {
    private let graph: GraphClient
    private let taskService: TaskService
    private let pushNotificationService: PushNotificationService

    init(graph: GraphClient, taskService: TaskService, pushNotificationService: PushNotificationService) {
        self.graph = graph
        self.taskService = taskService
        self.pushNotificationService = pushNotificationService
    }

    /// Channels visible to the signed-in user: Graph only returns private channels
    /// the caller is a member of, so this list is already correctly scoped between
    /// "everyone" (standard) and "certain people only" (private) channels.
    func fetchChannels() async throws -> [Channel] {
        let response: ChannelListResponse = try await graph.get(
            "teams/\(AppConfig.staffTeamId)/channels",
            queryItems: [URLQueryItem(name: "$select", value: "id,displayName,description,membershipType")]
        )
        return response.value
    }

    /// Members of a channel, used to populate the @mention picker. For a private
    /// channel this is exactly the restricted membership list; for a standard
    /// channel it's effectively the whole team.
    func fetchMembers(channelId: String) async throws -> [GraphUser] {
        let response: ChannelMembersResponse = try await graph.get(
            "teams/\(AppConfig.staffTeamId)/channels/\(channelId)/members"
        )
        return response.value.map { GraphUser(id: $0.userId, displayName: $0.displayName, userIdentityType: nil) }
    }

    func fetchMessages(channelId: String) async throws -> [ChatMessage] {
        let response: MessageListResponse = try await graph.get(
            "teams/\(AppConfig.staffTeamId)/channels/\(channelId)/messages",
            queryItems: [URLQueryItem(name: "$top", value: "50")]
        )
        return response.value.sorted { $0.createdDateTime < $1.createdDateTime }
    }

    /// Sends a plain message with no confirmation requirement.
    func sendMessage(channelId: String, text: String) async throws {
        let payload = MessageComposer.plainMessage(text: text)
        let _: ChatMessage = try await graph.post("teams/\(AppConfig.staffTeamId)/channels/\(channelId)/messages", body: payload)
    }

    /// Sends a message that tags `assignee` and opens a matching StaffTask so the
    /// tag can't silently get lost — it stays "open" until the assignee confirms it.
    /// Also asks the backend to push a "you've been tagged" alert; if that call
    /// fails (e.g. no connectivity right after sending), the task itself still
    /// exists and will simply be found the next time the assignee opens the app.
    func sendTaskMessage(channelId: String, channelName: String, text: String, assignee: GraphUser, createdBy: GraphUser) async throws {
        let payload = MessageComposer.taskMessage(text: text, mentioning: assignee)
        let sent: ChatMessage = try await graph.post("teams/\(AppConfig.staffTeamId)/channels/\(channelId)/messages", body: payload)

        let taskItemId = try await taskService.createTask(
            channelId: channelId,
            channelName: channelName,
            messageId: sent.id,
            summary: text,
            assignee: assignee,
            createdBy: createdBy
        )

        try? await pushNotificationService.notifyTagged(
            assignedToId: assignee.id,
            channelId: channelId,
            channelName: channelName,
            messageId: sent.id,
            taskItemId: taskItemId,
            taskSummary: text
        )
    }
}

struct ChannelMembersResponse: Decodable {
    let value: [ChannelMember]
}

struct ChannelMember: Decodable {
    let userId: String
    let displayName: String
}

// MARK: - Services/TaskService.swift

/// CRUD against the "StaffTasks" SharePoint list, which is the single source of
/// truth for every tagged, must-be-confirmed task across all channels.
/// See docs/SETUP.md for the list's column schema.
final class TaskService {
    private let graph: GraphClient

    init(graph: GraphClient) {
        self.graph = graph
    }

    private var listItemsPath: String {
        "sites/\(AppConfig.siteId)/lists/\(AppConfig.staffTasksListName)/items"
    }

    /// All open tasks assigned to `userId`, newest first.
    func fetchMyOpenTasks(userId: String) async throws -> [StaffTask] {
        // $filter on list item fields requires the "fields/<Column>" prefix.
        let response: ListItemsResponse = try await graph.get(
            listItemsPath,
            queryItems: [
                URLQueryItem(name: "expand", value: "fields"),
                URLQueryItem(name: "$filter", value: "fields/AssignedToId eq '\(userId)' and fields/Status eq 'Open'"),
                URLQueryItem(name: "$orderby", value: "createdDateTime desc")
            ]
        )
        return response.value.map { StaffTask(itemId: $0.id, fields: $0.fields, createdDateTime: $0.createdDateTime) }
    }

    /// All tasks (any status) created by or assigned to the user, for a personal
    /// history view. Open tasks first, then completed ones.
    func fetchAllMyTasks(userId: String) async throws -> [StaffTask] {
        let response: ListItemsResponse = try await graph.get(
            listItemsPath,
            queryItems: [
                URLQueryItem(name: "expand", value: "fields"),
                URLQueryItem(name: "$filter", value: "fields/AssignedToId eq '\(userId)' or fields/CreatedById eq '\(userId)'"),
                URLQueryItem(name: "$orderby", value: "createdDateTime desc")
            ]
        )
        return response.value
            .map { StaffTask(itemId: $0.id, fields: $0.fields, createdDateTime: $0.createdDateTime) }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .open }
                return lhs.createdDateTime > rhs.createdDateTime
            }
    }

    /// Returns the new list item's ID, so callers (e.g. ChatService, to trigger
    /// a push notification) can reference this specific task afterwards.
    @discardableResult
    func createTask(channelId: String, channelName: String, messageId: String, summary: String, assignee: GraphUser, createdBy: GraphUser) async throws -> String {
        let fields = StaffTaskFields(
            Title: summary,
            ChannelId: channelId,
            ChannelName: channelName,
            MessageId: messageId,
            AssignedToId: assignee.id,
            AssignedToName: assignee.displayName,
            CreatedById: createdBy.id,
            CreatedByName: createdBy.displayName,
            Status: StaffTask.Status.open.rawValue
        )
        let created: ListItem = try await graph.post(listItemsPath, body: NewListItem(fields: fields))
        return created.id
    }

    /// Marks a task done — this is what the "Done" button in a chat bubble or the
    /// My Tasks list calls.
    func markDone(itemId: String) async throws {
        try await graph.patch("\(listItemsPath)/\(itemId)/fields", body: StatusUpdate(Status: StaffTask.Status.done.rawValue))
    }

    func reopen(itemId: String) async throws {
        try await graph.patch("\(listItemsPath)/\(itemId)/fields", body: StatusUpdate(Status: StaffTask.Status.open.rawValue))
    }
}

private struct StatusUpdate: Encodable {
    let Status: String
}

// MARK: - Services/SearchService.swift

/// Searches SharePoint (documents, list items, and sites) through the Microsoft
/// Graph Search API, scoped to whatever the signed-in user already has permission
/// to see — no separate index or permissions model to maintain.
final class SearchService {
    private let graph: GraphClient

    init(graph: GraphClient) {
        self.graph = graph
    }

    func search(query: String) async throws -> [SharePointSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let body = GraphSearchRequestBody(requests: [
            SearchRequestEntry(entityTypes: ["driveItem", "listItem"], query: SearchQuery(queryString: query), from: 0, size: 25)
        ])
        let response: GraphSearchResponse = try await graph.post("search/query", body: body)
        let hits = response.value.flatMap { $0.hitsContainers.flatMap(\.hits) }
        return hits.map(SharePointSearchResult.init)
    }
}

// MARK: - Services/AssistantService.swift

/// Talks to the serverless legal-assistant relay (ServerlessBackend/marite-functions).
/// The app never calls Anthropic directly and never sees the API key — it just sends
/// the question plus short conversation history, authenticated with the user's own
/// Graph access token so the relay can confirm the caller is Marite staff.
final class AssistantService {
    private let authManager: AuthManager
    private let session: URLSession

    init(authManager: AuthManager, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    func ask(question: String, history: [AssistantMessage]) async throws -> (answer: String, citations: [AssistantCitation]) {
        let token = try await authManager.acquireToken()

        var request = URLRequest(url: AppConfig.assistantEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = AssistantRequestBody(
            question: question,
            history: history.suffix(10).map { AssistantHistoryTurn(role: $0.role.rawValue, text: $0.text) }
        )
        request.httpBody = try JSONEncoder.graph.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GraphError.invalidResponse
        }

        let decoded = try JSONDecoder.graph.decode(AssistantResponseBody.self, from: data)
        let citations = decoded.citations.map {
            AssistantCitation(documentTitle: $0.documentTitle, webUrl: $0.webUrl, excerpt: $0.excerpt)
        }
        return (decoded.answer, citations)
    }
}

// MARK: - Services/PushNotificationService.swift

/// Talks to the same Azure Function App as AssistantService, for the push
/// notification endpoints: registering/unregistering this device's APNs
/// token, and asking the backend to notify someone who was just tagged.
final class PushNotificationService {
    private let authManager: AuthManager
    private let session: URLSession

    init(authManager: AuthManager, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    func registerDevice(token: String) async throws {
        try await post(AppConfig.registerDeviceEndpoint, body: DeviceTokenRequest(deviceToken: token))
    }

    func unregisterDevice(token: String) async throws {
        try await post(AppConfig.unregisterDeviceEndpoint, body: DeviceTokenRequest(deviceToken: token))
    }

    /// Called right after a channel message @mentions someone and the
    /// matching StaffTask has been created, so the assignee gets an
    /// immediate alert rather than only finding out next time they open the app.
    func notifyTagged(assignedToId: String, channelId: String, channelName: String, messageId: String, taskItemId: String, taskSummary: String) async throws {
        let body = NotifyTaggedRequest(
            assignedToId: assignedToId,
            channelId: channelId,
            channelName: channelName,
            messageId: messageId,
            taskItemId: taskItemId,
            taskSummary: taskSummary
        )
        try await post(AppConfig.notifyTaggedEndpoint, body: body)
    }

    private func post<Body: Encodable>(_ url: URL, body: Body) async throws {
        let token = try await authManager.acquireToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.graph.encode(body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GraphError.invalidResponse
        }
    }
}

private struct DeviceTokenRequest: Encodable {
    let deviceToken: String
}

private struct NotifyTaggedRequest: Encodable {
    let assignedToId: String
    let channelId: String
    let channelName: String
    let messageId: String
    let taskItemId: String
    let taskSummary: String
}

// MARK: - Common/CommonViews.swift

struct LoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.red, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
    }
}

struct InitialsAvatar: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Circle()
            .fill(Color.orange.gradient)
            .overlay(Text(initials).font(.caption.bold()).foregroundStyle(.white))
            .frame(width: 32, height: 32)
    }
}

// MARK: - Features/Login/LoginView.swift

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Marite Connect")
                    .font(.largeTitle.bold())
                Text("Staff chat, tasks, SharePoint search, and the\nSectional Title Assistant — all in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                signIn()
            } label: {
                Label("Sign in with Microsoft", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 32)

            if let error = authManager.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text("Use your Marite Microsoft 365 account.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func signIn() {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        Task { await authManager.signIn(presentingViewController: rootVC) }
    }
}

// MARK: - Features/Channels/ChannelListViewModel.swift

@MainActor
final class ChannelListViewModel: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let chatService: ChatService

    init(chatService: ChatService) {
        self.chatService = chatService
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            channels = try await chatService.fetchChannels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Features/Channels/ChannelListView.swift

struct ChannelListView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @StateObject private var viewModel: ChannelListViewModel
    @State private var navPath = NavigationPath()

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: ChannelListViewModel(chatService: services.chatService))
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            content
                .navigationTitle("Channels")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let name = services.currentUser?.displayName {
                                Text(name)
                            }
                            Button("Sign Out", role: .destructive, action: signOut)
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .onChange(of: viewModel.channels) { _, _ in attemptDeepLink() }
                .onChange(of: deepLinkRouter.pendingChannelId) { _, _ in attemptDeepLink() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.channels.isEmpty {
            LoadingView()
        } else if let error = viewModel.errorMessage, viewModel.channels.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load channels", message: error)
        } else if viewModel.channels.isEmpty {
            EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No channels yet", message: "Channels created in the Marite Staff Team will show up here.")
        } else {
            List(viewModel.channels) { channel in
                NavigationLink(value: channel) {
                    ChannelRow(channel: channel)
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                MessageThreadView(channel: channel, services: services)
            }
        }
    }

    /// Opens the channel named in a tapped push notification, once both the
    /// channel list has loaded and a deep link is pending — whichever arrives second.
    private func attemptDeepLink() {
        guard let channelId = deepLinkRouter.pendingChannelId,
              let channel = viewModel.channels.first(where: { $0.id == channelId }) else { return }
        navPath.append(channel)
        deepLinkRouter.pendingChannelId = nil
    }

    private func signOut() {
        Task {
            if let token = pushManager.deviceToken {
                try? await services.pushNotificationService.unregisterDevice(token: token)
            }
            authManager.signOut()
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            Image(systemName: channel.membershipType.isRestricted ? "lock.fill" : "number")
                .foregroundStyle(channel.membershipType.isRestricted ? .orange : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayName).font(.body)
                if let description = channel.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Features/Channels/MessageThreadViewModel.swift

@MainActor
final class MessageThreadViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var members: [GraphUser] = []
    @Published private(set) var myOpenTaskItemIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var draft: String = ""
    @Published var mentionTarget: GraphUser?

    let channel: Channel
    private let chatService: ChatService
    private let taskService: TaskService
    private let currentUser: GraphUser?

    init(channel: Channel, chatService: ChatService, taskService: TaskService, currentUser: GraphUser?) {
        self.channel = channel
        self.chatService = chatService
        self.taskService = taskService
        self.currentUser = currentUser
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let messagesTask = chatService.fetchMessages(channelId: channel.id)
            async let membersTask = chatService.fetchMembers(channelId: channel.id)
            messages = try await messagesTask
            members = try await membersTask
            if let currentUser {
                let myTasks = try await taskService.fetchMyOpenTasks(userId: currentUser.id)
                myOpenTaskItemIds = Set(myTasks.filter { $0.channelId == channel.id }.map(\.messageId))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        guard canSend, let currentUser else { return }
        let text = draft
        let assignee = mentionTarget
        draft = ""
        mentionTarget = nil

        do {
            if let assignee {
                try await chatService.sendTaskMessage(channelId: channel.id, channelName: channel.displayName, text: text, assignee: assignee, createdBy: currentUser)
            } else {
                try await chatService.sendMessage(channelId: channel.id, text: text)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
            draft = text
            mentionTarget = assignee
        }
    }

    /// Whether the current viewer needs to confirm this message's tagged task.
    func isConfirmable(message: ChatMessage) -> Bool {
        guard let currentUser else { return false }
        return message.mentions.contains { $0.mentioned.user?.id == currentUser.id } && myOpenTaskItemIds.contains(message.id)
    }

    func confirmDone(message: ChatMessage) async {
        guard let currentUser else { return }
        do {
            let tasks = try await taskService.fetchMyOpenTasks(userId: currentUser.id)
            guard let task = tasks.first(where: { $0.messageId == message.id }) else { return }
            try await taskService.markDone(itemId: task.itemId)
            myOpenTaskItemIds.remove(message.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Features/Channels/MessageThreadView.swift

struct MessageThreadView: View {
    let channel: Channel

    @StateObject private var viewModel: MessageThreadViewModel

    init(channel: Channel, services: AppServices) {
        self.channel = channel
        _viewModel = StateObject(wrappedValue: MessageThreadViewModel(
            channel: channel,
            chatService: services.chatService,
            taskService: services.taskService,
            currentUser: services.currentUser
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                LoadingView()
            } else if viewModel.messages.isEmpty {
                EmptyStateView(systemImage: "bubble.left", title: "No messages yet", message: "Be the first to post in #\(channel.displayName).")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, needsConfirmation: viewModel.isConfirmable(message: message)) {
                                    Task { await viewModel.confirmDone(message: message) }
                                }
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            MessageComposerView(model: viewModel)
        }
        .navigationTitle(channel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let needsConfirmation: Bool
    let onConfirm: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            InitialsAvatar(name: message.senderName)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.senderName).font(.subheadline.bold())
                    Text(message.createdDateTime, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.body.plainText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.mentions.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(needsConfirmation ? "Waiting on your confirmation" : "Tagged: \(message.mentions.map(\.mentionText).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if needsConfirmation {
                        Button("Mark as Done", action: onConfirm)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

private extension MessageBody {
    /// Strips the `<at id="0">Name</at>` markup Graph uses for mentions so the
    /// bubble reads naturally; a production build might render this richly instead.
    var plainText: String {
        guard contentType == "html" else { return content }
        return content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

// MARK: - Features/Channels/MessageComposerView.swift

struct MessageComposerView: View {
    @ObservedObject var model: MessageThreadViewModel
    @State private var showingMentionPicker = false

    var body: some View {
        VStack(spacing: 6) {
            if let mentionTarget = model.mentionTarget {
                HStack {
                    Image(systemName: "at").foregroundStyle(.orange)
                    Text("Tagging \(mentionTarget.displayName) — they must confirm this is done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.mentionTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showingMentionPicker = true
                } label: {
                    Image(systemName: "at.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel("Tag someone")

                TextField("Message #\(model.channel.displayName)", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                }
                .disabled(!model.canSend)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
        .background(.bar)
        .sheet(isPresented: $showingMentionPicker) {
            MentionPickerView(members: model.members) { user in
                model.mentionTarget = user
                showingMentionPicker = false
            }
        }
    }
}

// MARK: - Features/Channels/MentionPickerView.swift

struct MentionPickerView: View {
    let members: [GraphUser]
    let onSelect: (GraphUser) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [GraphUser] {
        guard !query.isEmpty else { return members }
        return members.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.id) { user in
                Button {
                    onSelect(user)
                } label: {
                    HStack {
                        InitialsAvatar(name: user.displayName)
                        Text(user.displayName).foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search staff")
            .navigationTitle("Tag someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Features/Tasks/MyTasksViewModel.swift

@MainActor
final class MyTasksViewModel: ObservableObject {
    @Published private(set) var tasks: [StaffTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let taskService: TaskService
    private let currentUser: GraphUser?

    init(taskService: TaskService, currentUser: GraphUser?) {
        self.taskService = taskService
        self.currentUser = currentUser
    }

    var openCount: Int { tasks.filter { $0.status == .open }.count }

    func load() async {
        guard let currentUser else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tasks = try await taskService.fetchAllMyTasks(userId: currentUser.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ task: StaffTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let newStatus: StaffTask.Status = task.status == .open ? .done : .open
        do {
            if newStatus == .done {
                try await taskService.markDone(itemId: task.itemId)
            } else {
                try await taskService.reopen(itemId: task.itemId)
            }
            tasks[index].status = newStatus
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Features/Tasks/MyTasksView.swift

struct MyTasksView: View {
    @StateObject private var viewModel: MyTasksViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: MyTasksViewModel(taskService: services.taskService, currentUser: services.currentUser))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("My Tasks")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            LoadingView()
        } else if viewModel.tasks.isEmpty {
            EmptyStateView(systemImage: "checkmark.circle", title: "All clear", message: "Tasks tagged to you across every channel will show up here until you confirm them done.")
        } else {
            List {
                if viewModel.openCount > 0 {
                    Section("Open (\(viewModel.openCount))") {
                        ForEach(viewModel.tasks.filter { $0.status == .open }) { task in
                            TaskRow(task: task) { Task { await viewModel.toggle(task) } }
                        }
                    }
                }
                Section("Completed") {
                    ForEach(viewModel.tasks.filter { $0.status == .done }) { task in
                        TaskRow(task: task) { Task { await viewModel.toggle(task) } }
                    }
                }
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }
        }
    }
}

private struct TaskRow: View {
    let task: StaffTask
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .done ? .green : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.summary)
                        .font(.body)
                        .strikethrough(task.status == .done)
                        .foregroundStyle(.primary)
                    Text("#\(task.channelName) · from \(task.createdByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Features/Search/SharePointSearchViewModel.swift

@MainActor
final class SharePointSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [SharePointSearchResult] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    @Published private(set) var hasSearched = false

    private let searchService: SearchService
    private var searchTask: Task<Void, Never>?

    init(searchService: SearchService) {
        self.searchService = searchService
    }

    func search() {
        searchTask?.cancel()
        let text = query
        searchTask = Task {
            isSearching = true
            errorMessage = nil
            defer { isSearching = false }
            do {
                let found = try await searchService.search(query: text)
                if !Task.isCancelled {
                    results = found
                    hasSearched = true
                }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Features/Search/SharePointSearchView.swift

struct SharePointSearchView: View {
    @StateObject private var viewModel: SharePointSearchViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: SharePointSearchViewModel(searchService: services.searchService))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("SharePoint Search")
                .searchable(text: $viewModel.query, prompt: "Search leases, reports, minutes…")
                .onSubmit(of: .search) { viewModel.search() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching {
            LoadingView()
        } else if let error = viewModel.errorMessage {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Search failed", message: error)
        } else if !viewModel.hasSearched {
            EmptyStateView(systemImage: "magnifyingglass", title: "Search all of SharePoint", message: "Find documents, reports, and lists across every site you have access to — results respect your existing permissions.")
        } else if viewModel.results.isEmpty {
            EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "No results", message: "Try different keywords, or check the document is in a site you have access to.")
        } else {
            List(viewModel.results) { result in
                Link(destination: URL(string: result.webUrl) ?? URL(string: "https://portal.office.com")!) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title).font(.body).foregroundStyle(.primary)
                        if !result.snippet.isEmpty {
                            Text(result.snippet.strippingHighlightTags)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

private extension String {
    /// Graph search summaries wrap matched terms in <c0>...</c0>; strip for a plain preview.
    var strippingHighlightTags: String {
        replacingOccurrences(of: "<c0>", with: "").replacingOccurrences(of: "</c0>", with: "")
            .replacingOccurrences(of: "<ddd/>", with: "…")
    }
}

// MARK: - Features/Assistant/SectionalTitleAssistantViewModel.swift

@MainActor
final class SectionalTitleAssistantViewModel: ObservableObject {
    @Published private(set) var messages: [AssistantMessage] = [
        AssistantMessage(
            role: .assistant,
            text: "Hi, I'm the Sectional Title Assistant. Ask me about the Sectional Titles Schemes Management Act, CSOS rulings, or describe a scenario at one of our schemes and I'll help you work out how to handle it — with citations to the actual Act sections or CSOS orders where they apply."
        )
    ]
    @Published var draft = ""
    @Published private(set) var isThinking = false
    @Published var errorMessage: String?

    private let assistantService: AssistantService

    init(assistantService: AssistantService) {
        self.assistantService = assistantService
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking }

    func send() async {
        guard canSend else { return }
        let question = draft
        draft = ""
        errorMessage = nil
        messages.append(AssistantMessage(role: .user, text: question))

        isThinking = true
        defer { isThinking = false }
        do {
            let history = messages
            let (answer, citations) = try await assistantService.ask(question: question, history: history)
            messages.append(AssistantMessage(role: .assistant, text: answer, citations: citations))
        } catch {
            errorMessage = "Couldn't reach the Legal Assistant: \(error.localizedDescription)"
        }
    }
}

// MARK: - Features/Assistant/SectionalTitleAssistantView.swift

struct SectionalTitleAssistantView: View {
    @StateObject private var viewModel: SectionalTitleAssistantViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: SectionalTitleAssistantViewModel(assistantService: services.assistantService))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                AssistantBubble(message: message).id(message.id)
                            }
                            if viewModel.isThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Checking the Act and CSOS records…").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask a question or describe a scenario…", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "paperplane.fill").font(.title2)
                    }
                    .disabled(!viewModel.canSend)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Legal Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AssistantBubble: View {
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .padding(12)
                .background(message.role == .user ? Color.orange.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if !message.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.citations) { citation in
                        Link(destination: URL(string: citation.webUrl) ?? URL(string: "https://portal.office.com")!) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "doc.text.fill").font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.documentTitle).font(.caption.bold())
                                    Text(citation.excerpt).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - App/RootTabView.swift

struct RootTabView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        TabView {
            ChannelListView(services: services)
                .tabItem { Label("Channels", systemImage: "bubble.left.and.bubble.right.fill") }

            MyTasksView(services: services)
                .tabItem { Label("My Tasks", systemImage: "checkmark.circle.fill") }

            SharePointSearchView(services: services)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            SectionalTitleAssistantView(services: services)
                .tabItem { Label("Legal Assistant", systemImage: "building.columns.fill") }
        }
    }
}

// MARK: - App/MariteConnectApp.swift

@main
struct MariteConnectApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView(authManager: authManager)
                .environmentObject(authManager)
                .environmentObject(DeepLinkRouter.shared)
        }
    }
}

/// Switches between the sign-in screen and the main tab experience based on
/// auth state. `services` is built from the very same AuthManager instance the
/// rest of the app uses, so every Graph call shares one signed-in session.
struct RootView: View {
    @ObservedObject private var authManager: AuthManager
    @StateObject private var services: AppServices
    @ObservedObject private var pushManager = PushNotificationManager.shared

    init(authManager: AuthManager) {
        _authManager = ObservedObject(wrappedValue: authManager)
        _services = StateObject(wrappedValue: AppServices(authManager: authManager))
    }

    var body: some View {
        Group {
            if authManager.isSignedIn {
                RootTabView()
                    .environmentObject(services)
                    .task {
                        await services.loadCurrentUser()
                        await pushManager.requestAuthorizationAndRegister()
                    }
                    .onReceive(pushManager.$deviceToken.compactMap { $0 }) { token in
                        Task { try? await services.pushNotificationService.registerDevice(token: token) }
                    }
            } else {
                LoginView()
            }
        }
        .animation(.default, value: authManager.isSignedIn)
    }
}
