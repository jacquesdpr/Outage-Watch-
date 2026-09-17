import Foundation

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
