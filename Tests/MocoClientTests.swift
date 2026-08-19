import Testing
import Foundation
@testable import MocoCompanion

/// Covers `MocoClient.execute()`'s HTTP-status → `MocoError` mapping, which
/// had zero direct coverage. Requests are routed through `StubURLProtocol`
/// registered on an ephemeral `URLSession` so nothing ever touches the
/// network; every request must be handled by the stub or the test fails.
///
/// `.serialized` because `StubURLProtocol.handler` is process-global mutable
/// state — running these tests concurrently with each other would let one
/// test's handler answer another test's request.
@Suite("MocoClient", .serialized)
struct MocoClientTests {

    // MARK: - Helpers

    private func makeClient(status: Int, headers: [String: String] = [:], body: Data) -> MocoClient {
        StubURLProtocol.handler = { _ in (status, headers, body) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return MocoClient(subdomain: "test", apiKey: "key", session: session)
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    /// Assert that `operation` throws a `MocoError` satisfying `matches`.
    private func expectMocoError(
        _ description: String,
        matches: (MocoError) -> Bool,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(description) but the call succeeded")
        } catch let error as MocoError {
            #expect(matches(error), "Expected \(description), got \(error)")
        } catch {
            Issue.record("Expected MocoError for \(description), got \(type(of: error)): \(error)")
        }
    }

    // MARK: - Status Mapping

    @Test("401 maps to .unauthorized")
    func status401() async {
        let client = makeClient(status: 401, body: Data())
        await expectMocoError("401 → .unauthorized", matches: {
            if case .unauthorized = $0 { true } else { false }
        }) {
            _ = try await client.fetchSession()
        }
    }

    @Test("404 maps to a not-found error")
    func status404() async {
        let client = makeClient(status: 404, body: Data())
        await expectMocoError("404 → isNotFound", matches: { $0.isNotFound }) {
            _ = try await client.fetchSession()
        }
    }

    @Test("403 maps to a forbidden error")
    func status403() async {
        let client = makeClient(status: 403, body: Data())
        await expectMocoError("403 → isForbidden", matches: { $0.isForbidden }) {
            _ = try await client.fetchSession()
        }
    }

    @Test("422 surfaces the server's validation message")
    func status422() async {
        let body = json(["message": "Description is required"])
        let client = makeClient(status: 422, body: body)
        await expectMocoError("422 → .validationError with server message", matches: {
            if case .validationError(let message) = $0 { return message == "Description is required" }
            return false
        }) {
            _ = try await client.fetchSession()
        }
    }

    @Test("429 with Retry-After maps to a rate-limit error carrying the delay")
    func status429WithRetryAfter() async {
        let client = makeClient(status: 429, headers: ["Retry-After": "30"], body: Data())
        await expectMocoError("429 → .rateLimited(retryAfter: 30)", matches: {
            if case .rateLimited(let retryAfter) = $0 { return retryAfter == 30 }
            return false
        }) {
            _ = try await client.fetchSession()
        }
    }

    @Test("500 maps to a server error carrying the status code")
    func status500() async {
        let body = json(["message": "Internal error"])
        let client = makeClient(status: 500, body: body)
        await expectMocoError("500 → .serverError(500, _)", matches: {
            if case .serverError(let code, _) = $0 { return code == 500 }
            return false
        }) {
            _ = try await client.fetchSession()
        }
    }

    @Test("Malformed JSON on a 200 response maps to .decodingError")
    func malformedJSONOn200() async {
        let client = makeClient(status: 200, body: Data("not json".utf8))
        await expectMocoError("malformed 200 body → .decodingError", matches: {
            if case .decodingError = $0 { true } else { false }
        }) {
            _ = try await client.fetchSession()
        }
    }

    // MARK: - Happy Path

    @Test("A well-formed 200 response decodes successfully")
    func happyPathDecode() async throws {
        let body = json(["id": 1, "uuid": "abc-123"])
        let client = makeClient(status: 200, body: body)

        let session = try await client.fetchSession()

        #expect(session.id == 1)
        #expect(session.uuid == "abc-123")
    }
}

// MARK: - StubURLProtocol

/// A `URLProtocol` stub that answers every request with a canned
/// (statusCode, headers, body) triple, without ever touching the network.
/// `canInit` returning `true` unconditionally means the stub must always
/// have a handler installed before use — an unhandled request fails loud
/// via `didFailWithError` rather than silently falling through to the
/// network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (statusCode, headers, data) = handler(request)
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
