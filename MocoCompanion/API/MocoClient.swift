import Foundation
import os

/// Async client for the Moco REST API.
///
/// All methods are async/throws. The client is a value type (struct) and `Sendable`,
/// safe to use from any concurrency context.
struct MocoClient: MocoClientProtocol, Sendable {
    let subdomain: String
    let apiKey: String

    private let session: URLSession
    private let rateGate: APIRateGate?
    private let logger = Logger(category: "MocoAPI")

    // Shared formatters — allocated once, thread-safe for Sendable structs.
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    var baseURL: URL? {
        guard Self.isValidSubdomain(subdomain) else { return nil }
        return URL(string: "https://\(subdomain).mocoapp.com/api/v1")
    }

    /// Validate that a subdomain contains only allowed characters (a-z, 0-9, hyphen).
    static func isValidSubdomain(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[a-zA-Z0-9-]+$"#, options: .regularExpression) != nil
    }

    init(subdomain: String, apiKey: String, session: URLSession = .shared, rateGate: APIRateGate? = nil) {
        self.subdomain = subdomain
        self.apiKey = apiKey
        self.session = session
        self.rateGate = rateGate
    }

    // MARK: - Projects

    func fetchAssignedProjects(active: Bool = true) async throws -> [MocoProject] {
        var components = try urlComponents(path: "projects/assigned")
        if active {
            components.queryItems = [URLQueryItem(name: "active", value: "true")]
        }
        return try await perform(request: makeRequest(.get, url: components.requireURL()))
    }

    // MARK: - Session

    func fetchSession() async throws -> MocoSession {
        return try await perform(request: makeRequest(.get, path: "session"))
    }

    func fetchUserProfile(userId: Int) async throws -> MocoUserProfile {
        // Use /users?ids[]=<id> instead of /users/<id> — the latter
        // requires admin permissions and returns 403 for regular users.
        var components = try urlComponents(path: "users")
        components.queryItems = [URLQueryItem(name: "ids[]", value: String(userId))]
        let users: [MocoUserProfile] = try await perform(request: makeRequest(.get, url: components.requireURL()))
        guard let user = users.first else {
            throw MocoError.notFound
        }
        return user
    }

    // MARK: - Activities

    func fetchActivities(from: String, to: String, userId: Int? = nil) async throws -> [MocoActivity] {
        var components = try urlComponents(path: "activities")
        var queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ]
        if let userId {
            queryItems.append(URLQueryItem(name: "user_id", value: String(userId)))
        }
        components.queryItems = queryItems
        return try await perform(request: makeRequest(.get, url: components.requireURL()))
    }

    func createActivity(
        date: String,
        projectId: Int,
        taskId: Int,
        description: String,
        seconds: Int = 0,
        tag: String? = nil
    ) async throws -> MocoActivity {
        let body = CreateActivityRequest(
            date: date,
            projectId: projectId,
            taskId: taskId,
            description: description,
            seconds: seconds,
            tag: tag
        )
        var request = try makeRequest(.post, path: "activities")
        request.httpBody = try Self.encoder.encode(body)
        return try await perform(request: request)
    }

    func startTimer(activityId: Int) async throws -> MocoActivity {
        return try await perform(request: makeRequest(.patch, path: "activities/\(activityId)/start_timer"))
    }

    func updateActivity(activityId: Int, description: String, tag: String?) async throws -> MocoActivity {
        let body = UpdateActivityRequest(description: description, tag: tag)
        var request = try makeRequest(.put, path: "activities/\(activityId)")
        request.httpBody = try Self.encoder.encode(body)
        return try await perform(request: request)
    }

    func updateActivity(activityId: Int, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        let body = UpdateActivityRequest(description: description, tag: tag, seconds: seconds)
        var request = try makeRequest(.put, path: "activities/\(activityId)")
        request.httpBody = try Self.encoder.encode(body)
        return try await perform(request: request)
    }

    func updateActivity(activityId: Int, projectId: Int?, taskId: Int?, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        let body = UpdateActivityRequest(projectId: projectId, taskId: taskId, description: description, tag: tag, seconds: seconds)
        var request = try makeRequest(.put, path: "activities/\(activityId)")
        request.httpBody = try Self.encoder.encode(body)
        return try await perform(request: request)
    }

    func stopTimer(activityId: Int) async throws -> MocoActivity {
        return try await perform(request: makeRequest(.patch, path: "activities/\(activityId)/stop_timer"))
    }

    func deleteActivity(activityId: Int) async throws {
        _ = try await execute(request: makeRequest(.delete, path: "activities/\(activityId)"))
    }

    // MARK: - Employments

    func fetchEmployments(from: String) async throws -> [MocoEmployment] {
        var components = try urlComponents(path: "users/employments")
        components.queryItems = [URLQueryItem(name: "from", value: from)]
        return try await perform(request: makeRequest(.get, url: components.requireURL()))
    }

    // MARK: - Schedules (Absences)

    func fetchSchedules(from: String, to: String) async throws -> [MocoSchedule] {
        var components = try urlComponents(path: "schedules")
        components.queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ]
        return try await perform(request: makeRequest(.get, url: components.requireURL()))
    }

    // MARK: - Planning Entries

    func fetchPlanningEntries(period: String, userId: Int? = nil) async throws -> [MocoPlanningEntry] {
        var components = try urlComponents(path: "planning_entries")
        var queryItems = [URLQueryItem(name: "period", value: period)]
        if let userId {
            queryItems.append(URLQueryItem(name: "user_id", value: String(userId)))
        }
        components.queryItems = queryItems
        return try await perform(request: makeRequest(.get, url: components.requireURL()))
    }

    // MARK: - Budget (Project Details, Reports, Contracts)

    func fetchProject(id: Int) async throws -> MocoFullProject {
        return try await perform(request: makeRequest(.get, path: "projects/\(id)"))
    }

    func fetchProjectReport(projectId: Int) async throws -> MocoProjectReport {
        return try await perform(request: makeRequest(.get, path: "projects/\(projectId)/report"))
    }

    func fetchProjectContracts(projectId: Int) async throws -> [MocoProjectContract] {
        return try await perform(request: makeRequest(.get, path: "projects/\(projectId)/contracts"))
    }

    // MARK: - Private

    private enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    /// Build URLComponents for a path, throwing if the base URL is invalid.
    private func urlComponents(path: String) throws -> URLComponents {
        guard let base = baseURL else {
            throw MocoError.invalidConfiguration
        }
        guard let components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw MocoError.invalidConfiguration
        }
        return components
    }

    /// Build a request from a path string. Throws if URL construction fails.
    private func makeRequest(_ method: HTTPMethod, path: String) throws -> URLRequest {
        guard let base = baseURL else {
            throw MocoError.invalidConfiguration
        }
        return makeRequest(method, url: base.appendingPathComponent(path))
    }

    private func makeRequest(_ method: HTTPMethod, url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Token token=\(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Core network execution: send request, log timing, map HTTP errors to MocoError.
    /// Passes through the rate gate (if present) before sending.
    private func execute(request: URLRequest) async throws -> Data {
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        logger.debug("\(method) \(url)")

        // Rate gate: wait for capacity before sending
        await rateGate?.waitForCapacity()
        await rateGate?.recordRequest()

        let startTime = CFAbsoluteTimeGetCurrent()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("Network error: \(urlError.localizedDescription)")
            await AppLogger.shared.apiRequest(method: method, url: url, duration: duration, error: urlError.localizedDescription)
            throw MocoError.networkError(urlError)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MocoError.serverError(statusCode: 0, message: "Invalid response type")
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.debug("Response: \(httpResponse.statusCode) (\(data.count) bytes)")

        switch httpResponse.statusCode {
        case 200...299:
            await AppLogger.shared.apiRequest(method: method, url: url, statusCode: httpResponse.statusCode, duration: duration)
            return data
        case 401:
            await AppLogger.shared.apiRequest(method: method, url: url, statusCode: 401, duration: duration, error: "Unauthorized")
            throw MocoError.unauthorized
        case 404:
            await AppLogger.shared.apiRequest(method: method, url: url, statusCode: 404, duration: duration, error: "Not found")
            throw MocoError.notFound
        case 422:
            let message = Self.extractErrorMessage(from: data, fallback: "Unprocessable entity")
            await AppLogger.shared.apiRequest(method: method, url: url, statusCode: 422, duration: duration, error: message)
            throw MocoError.validationError(message: message)
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            await AppLogger.shared.apiRequest(method: method, url: url, statusCode: 429, duration: duration, error: "Rate limited")
            await rateGate?.recordRetryAfter(seconds: retryAfter)
            throw MocoError.rateLimited(retryAfter: retryAfter)
        default:
            let message = Self.extractErrorMessage(from: data, fallback: "HTTP \(httpResponse.statusCode)")
            await AppLogger.shared.apiRequest(method: method, url: url, statusCode: httpResponse.statusCode, duration: duration, error: message)
            throw MocoError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Extract a human-readable error message from a Moco API error response body.
    /// Handles common shapes: `{"message": ...}`, `{"error": ...}`, `{"errors": {...}}`,
    /// `[{"key": ..., "message": ...}]`, plain text, and empty bodies.
    static func extractErrorMessage(from data: Data, fallback: String) -> String {
        // Empty body → use fallback (prior code returned "" which logged as "ERROR: ")
        guard !data.isEmpty, let raw = String(data: data, encoding: .utf8) else {
            return fallback
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        // Try to parse as JSON and extract a readable message
        if let json = try? JSONSerialization.jsonObject(with: data) {
            // Shape: {"message": "..."} or {"error": "..."}
            if let dict = json as? [String: Any] {
                if let msg = dict["message"] as? String, !msg.isEmpty { return msg }
                if let err = dict["error"] as? String, !err.isEmpty { return err }
                // Shape: {"errors": {"field": ["msg1", "msg2"]}}
                if let errors = dict["errors"] as? [String: [String]] {
                    let parts = errors.map { "\($0.key): \($0.value.joined(separator: ", "))" }
                    if !parts.isEmpty { return parts.joined(separator: "; ") }
                }
                // Shape: {"errors": ["msg1", "msg2"]}
                if let errors = dict["errors"] as? [String], !errors.isEmpty {
                    return errors.joined(separator: "; ")
                }
            }
            // Shape: [{"key": "field", "message": "msg"}]
            if let array = json as? [[String: Any]] {
                let messages = array.compactMap { item -> String? in
                    let msg = item["message"] as? String
                    if let key = item["key"] as? String, let msg, !msg.isEmpty {
                        return "\(key): \(msg)"
                    }
                    return msg
                }
                if !messages.isEmpty { return messages.joined(separator: "; ") }
            }
            // Shape: ["msg1", "msg2"]
            if let array = json as? [String], !array.isEmpty {
                return array.joined(separator: "; ")
            }
        }

        // Fall back to the raw body (JSON or plain text)
        return trimmed
    }

    /// Execute and decode the response as a Decodable type.
    private func perform<T: Decodable & Sendable>(request: URLRequest) async throws -> T {
        let data = try await execute(request: request)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            let detail = String(describing: decodingError)
            logger.error("Decoding failed: \(detail)")
            let method = request.httpMethod ?? "?"
            let url = request.url?.absoluteString ?? "?"
            await AppLogger.shared.apiRequest(method: method, url: url, statusCode: 200, duration: 0, error: "Decoding: \(detail)")
            throw MocoError.decodingError(detail)
        }
    }
}

// MARK: - Debug Safety

extension MocoClient: CustomDebugStringConvertible {
    var debugDescription: String {
        "MocoClient(subdomain: \(subdomain), apiKey: [REDACTED])"
    }
}

// MARK: - URLComponents Helper

private extension URLComponents {
    /// Get the URL or throw if construction failed.
    func requireURL() throws -> URL {
        guard let url else {
            throw MocoError.invalidConfiguration
        }
        return url
    }
}
