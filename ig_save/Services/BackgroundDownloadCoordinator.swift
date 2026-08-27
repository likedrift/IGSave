import Foundation

@MainActor
final class BackgroundDownloadCoordinator: NSObject, @unchecked Sendable {
    static let shared = BackgroundDownloadCoordinator()
    static let sessionIdentifier = "com.haru.ig-save.media-downloads"

    private typealias DownloadContinuation = CheckedContinuation<URL, Error>

    private let lock = NSLock()
    private var continuations: [Int: [DownloadContinuation]] = [:]
    private var completedResults: [Int: Result<URL, Error>] = [:]
    private var backgroundEventsCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
    }

    func download(
        request: URLRequest,
        identifier: String,
        fileExtension: String
    ) async throws -> URL {
        let destinationURL = try Self.completedFileURL(
            identifier: identifier,
            fileExtension: fileExtension
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        let existingTasks = await session.allTasks
        let existingTask = existingTasks
            .compactMap { $0 as? URLSessionDownloadTask }
            .first { Self.transferIdentifier(from: $0.taskDescription) == identifier }
        let task = existingTask ?? session.downloadTask(with: request)
        let isNewTask = existingTask == nil

        if isNewTask {
            task.taskDescription = Self.taskDescription(
                identifier: identifier,
                fileExtension: fileExtension
            )
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    lock.unlock()
                    continuation.resume(returning: destinationURL)
                    return
                }
                if let completedResult = completedResults.removeValue(forKey: task.taskIdentifier) {
                    lock.unlock()
                    continuation.resume(with: completedResult)
                    return
                }
                continuations[task.taskIdentifier, default: []].append(continuation)
                lock.unlock()

                if isNewTask || task.state == .suspended {
                    task.resume()
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(identifier: identifier)
            }
        }
    }

    func setBackgroundEventsCompletionHandler(_ completionHandler: @escaping () -> Void) {
        _ = session
        lock.lock()
        backgroundEventsCompletionHandler = completionHandler
        lock.unlock()
    }

    func cancel(identifier: String) {
        Task {
            let tasks = await session.allTasks
            for task in tasks where Self.transferIdentifier(from: task.taskDescription) == identifier {
                task.cancel()
            }
        }
    }

    nonisolated static func cacheDirectoryURL() throws -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundMedia", isDirectory: true)
    }

    private static func completedFileURL(identifier: String, fileExtension: String) throws -> URL {
        let directory = try cacheDirectoryURL()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let filename = fileExtension.isEmpty ? identifier : "\(identifier).\(fileExtension)"
        return directory.appendingPathComponent(filename)
    }

    private static func taskDescription(identifier: String, fileExtension: String) -> String {
        "\(identifier)|\(fileExtension)"
    }

    private static func transferIdentifier(from taskDescription: String?) -> String? {
        taskDescription?.split(separator: "|", maxSplits: 1).first.map(String.init)
    }

    private static func fileExtension(from taskDescription: String?) -> String {
        guard let taskDescription,
              let separator = taskDescription.firstIndex(of: "|") else {
            return ""
        }
        return String(taskDescription[taskDescription.index(after: separator)...])
    }

    private func finish(taskIdentifier: Int, result: Result<URL, Error>) {
        lock.lock()
        completedResults[taskIdentifier] = result
        lock.unlock()
    }

    private func complete(taskIdentifier: Int, fallbackError: Error?) {
        lock.lock()
        let result = completedResults.removeValue(forKey: taskIdentifier) ?? .failure(
            fallbackError ?? MediaDownloaderError.invalidResponse
        )
        let waitingContinuations = continuations.removeValue(forKey: taskIdentifier) ?? []
        if waitingContinuations.isEmpty {
            completedResults[taskIdentifier] = result
            if completedResults.count > 50,
               let staleTaskIdentifier = completedResults.keys.first(where: { $0 != taskIdentifier }) {
                completedResults.removeValue(forKey: staleTaskIdentifier)
            }
        }
        lock.unlock()

        for continuation in waitingContinuations {
            continuation.resume(with: result)
        }
    }
}

extension BackgroundDownloadCoordinator: @preconcurrency URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let identifier = Self.transferIdentifier(from: downloadTask.taskDescription),
              let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            finish(taskIdentifier: downloadTask.taskIdentifier, result: .failure(MediaDownloaderError.invalidResponse))
            return
        }

        do {
            let destinationURL = try Self.completedFileURL(
                identifier: identifier,
                fileExtension: Self.fileExtension(from: downloadTask.taskDescription)
            )
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            finish(taskIdentifier: downloadTask.taskIdentifier, result: .success(destinationURL))
        } catch {
            finish(taskIdentifier: downloadTask.taskIdentifier, result: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            complete(taskIdentifier: task.taskIdentifier, fallbackError: CancellationError())
        } else {
            complete(taskIdentifier: task.taskIdentifier, fallbackError: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let completionHandler = backgroundEventsCompletionHandler
        backgroundEventsCompletionHandler = nil
        lock.unlock()

        DispatchQueue.main.async {
            completionHandler?()
        }
    }
}
