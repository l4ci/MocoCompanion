import Foundation

/// Errors from the Moco API client.
enum MocoError: Error, LocalizedError, Sendable {
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case notFound
    case validationError(message: String)
    case serverError(statusCode: Int, message: String)
    case networkError(URLError)
    case decodingError(String)
    case invalidConfiguration

    /// Convert any Error to a MocoError, preserving it if already one.
    static func from(_ error: any Error) -> MocoError {
        if let me = error as? MocoError { return me }
        return .serverError(statusCode: 0, message: error.localizedDescription)
    }

    /// True when the error stems from Moco rejecting our credentials or
    /// the API not being configured — i.e. user action (re-entering the
    /// API key in Settings) is required. Transient issues like rate
    /// limiting, network blips, or server errors don't qualify: those
    /// will heal on retry and don't warrant a menubar alarm.
    /// True when the resource is gone or inaccessible on the server —
    /// 403 (locked/forbidden) or 404 (deleted). Used by SyncEngine to
    /// stop retrying deletes that will never succeed.
    var isGone: Bool {
        switch self {
        case .notFound:
            return true
        case .serverError(let code, _) where code == 403:
            return true
        default:
            return false
        }
    }

    var requiresUserReauthentication: Bool {
        switch self {
        case .unauthorized, .invalidConfiguration:
            return true
        case .rateLimited, .notFound, .validationError, .serverError,
             .networkError, .decodingError:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid API key or unauthorized access. Check your Moco credentials."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited by Moco. Retry in \(seconds) seconds."
            }
            return "Rate limited by Moco. Try again shortly."
        case .notFound:
            return "Resource not found in Moco."
        case .validationError(let message):
            return "Moco rejected the request: \(message)"
        case .serverError(let code, let message):
            return "Moco server error (\(code)): \(message)"
        case .networkError(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .decodingError(let detail):
            return "Failed to decode Moco response: \(detail)"
        case .invalidConfiguration:
            return "Moco API not configured. Set subdomain and API key in Settings."
        }
    }
}
