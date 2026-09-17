import Foundation

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
