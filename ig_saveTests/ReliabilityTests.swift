import Foundation
import Testing
@testable import IGSave

struct ReliabilityTests {
    @Test("临时网络错误会重试且永久错误不会重试")
    func classifiesRetryableFailures() {
        let policy = NetworkRetryPolicy(maximumAttempts: 3, baseDelay: 1, maximumDelay: 5)

        #expect(policy.shouldRetry(statusCode: 429, afterAttempt: 1))
        #expect(policy.shouldRetry(statusCode: 503, afterAttempt: 2))
        #expect(!policy.shouldRetry(statusCode: 404, afterAttempt: 1))
        #expect(!policy.shouldRetry(statusCode: 503, afterAttempt: 3))
        #expect(policy.shouldRetry(error: URLError(.timedOut), afterAttempt: 1))
        #expect(!policy.shouldRetry(error: URLError(.cancelled), afterAttempt: 1))
    }

    @Test("退避延迟遵循指数增长、Retry-After 和上限")
    func calculatesRetryDelay() {
        let policy = NetworkRetryPolicy(maximumAttempts: 4, baseDelay: 1, maximumDelay: 5)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(policy.delay(afterAttempt: 1, now: now) == 1)
        #expect(policy.delay(afterAttempt: 2, now: now) == 2)
        #expect(policy.delay(afterAttempt: 4, now: now) == 5)
        #expect(policy.delay(afterAttempt: 1, retryAfter: "3", now: now) == 3)
        #expect(policy.delay(afterAttempt: 1, retryAfter: "20", now: now) == 5)
    }

    @Test("主文件损坏时会从最近的有效备份恢复")
    func restoresDurableJSONBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("igsave-storage-tests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(DurableJSONStore.persist(["first"], to: url))
        #expect(FileManager.default.fileExists(atPath: DurableJSONStore.backupURL(for: url).path))
        #expect(DurableJSONStore.persist(["second"], to: url))
        try Data("not-json".utf8).write(to: url, options: .atomic)

        let restored = DurableJSONStore.load([String].self, from: url)
        let restoredPrimary = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))

        #expect(restored == ["first"])
        #expect(restoredPrimary == ["first"])
    }

    @Test("重复检查使用内存中的媒体库且能忽略链接跟踪参数")
    func findsPreviousSaveInMemory() throws {
        let save = RecentSave(
            username: "@example",
            itemCount: 1,
            contentKind: .post,
            sourceURL: "https://www.instagram.com/p/example/?utm_source=share",
            previewFilename: nil
        )

        let match = RecentSaveStore.previousSave(
            for: "https://www.instagram.com/p/example/?igsh=tracking",
            in: [save]
        )

        #expect(match?.id == save.id)
    }

    @Test("解析会从临时服务错误恢复并采用跳转后的内容地址")
    func resolverRetriesAndUsesFinalURL() async throws {
        let initialURL = try #require(URL(string: "https://www.instagram.com/share/reel/example"))
        let finalURL = try #require(URL(string: "https://www.instagram.com/reel/final-code/"))
        MockInstagramURLProtocol.configure(finalURL: finalURL)
        defer { MockInstagramURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockInstagramURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let resolver = InstagramMediaResolver(
            session: session,
            retryPolicy: NetworkRetryPolicy(maximumAttempts: 2, baseDelay: 0, maximumDelay: 0)
        )
        let resolution = try await resolver.resolve(initialURL.absoluteString)

        #expect(MockInstagramURLProtocol.requestCount == 2)
        #expect(resolution.sourceURL == finalURL)
        #expect(resolution.contentKind == .reel)
        #expect(resolution.assets.count == 1)
        #expect(resolution.assets.first?.kind == .image)
    }
}

private final class MockInstagramURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var configuredFinalURL: URL?
    nonisolated(unsafe) private static var storedRequestCount = 0

    static var requestCount: Int {
        lock.withLock { storedRequestCount }
    }

    static func configure(finalURL: URL) {
        lock.withLock {
            configuredFinalURL = finalURL
            storedRequestCount = 0
        }
    }

    static func reset() {
        lock.withLock {
            configuredFinalURL = nil
            storedRequestCount = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let state = Self.lock.withLock { () -> (URL?, Int) in
            Self.storedRequestCount += 1
            return (Self.configuredFinalURL, Self.storedRequestCount)
        }
        guard let finalURL = state.0 else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if state.1 == 1 {
            let response = HTTPURLResponse(
                url: request.url ?? finalURL,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: ["Retry-After": "0"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let html = #"<html><head><meta property="og:image" content="https://cdninstagram.com/media.jpg"></head></html>"#
        let response = HTTPURLResponse(
            url: finalURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
