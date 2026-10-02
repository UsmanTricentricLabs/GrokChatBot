//
//  GatewayTestSupport.swift
//  GrokTests
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation
@testable import Grok

/// Intercepts Gateway traffic so tests exercise the real client against
/// scripted responses. No request leaves the machine and no provider
/// credential is involved.
final class StubURLProtocol: URLProtocol {

    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data()
        var headers: [String: String] = [:]
        var error: URLError?
        /// Delays the response so cancellation can be observed.
        var delay: TimeInterval = 0
    }

    nonisolated(unsafe) static var stub = Stub()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func reset() {
        stub = Stub()
        lastRequest = nil
        lastBody = nil
    }

    /// The decoded JSON body of the most recent request.
    static func lastJSON() -> [String: Any]? {
        guard let lastBody else { return nil }
        return try? JSONSerialization.jsonObject(with: lastBody) as? [String: Any]
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLProtocol strips httpBody, so the stream carries the payload.
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.drain)

        let stub = Self.stub
        let deliver = { [weak self] in
            guard let self else { return }

            if let error = stub.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        if stub.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

extension StubURLProtocol.Stub {
    static func json(_ raw: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        StubURLProtocol.Stub(
            statusCode: status,
            body: Data(raw.utf8),
            headers: headers
        )
    }
}

enum TestFixtures {
    static let chatResponse = """
        {
          "request_id": "req_test_chat",
          "created_at": "2026-10-01T12:00:00.000Z",
          "model": "grok-4.3",
          "provider": "xai",
          "message": { "role": "assistant", "content": "Hello there." },
          "finish_reason": "stop"
        }
        """

    /// A 1×1 PNG, so decoding produces a real image without shipping a fixture.
    static let pngBase64 = """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """

    static var imageResponse: String {
        """
        {
          "request_id": "req_test_image",
          "model": "gemini-2.5-flash-image",
          "image": { "data": "\(pngBase64)", "mime_type": "image/png" }
        }
        """
    }

    static func error(_ code: String, message: String = "Test failure.", details: String = "") -> String {
        """
        { "error": { "code": "\(code)", "message": "\(message)", "request_id": "req_test_error"\(details) } }
        """
    }
}
