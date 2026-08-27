//
//  DownloadViewModel.swift
//  ig_save
//

import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var jobs: [SaveJob] = SaveJobStore.load()
    @Published private(set) var isWorking = false
    @Published private(set) var recentSaves: [RecentSave] = RecentSaveStore.load()
    @Published private(set) var hasInstagramSession = false
    @Published private(set) var instagramSessionState: InstagramSessionState = .disconnected
    @Published var isShowingInstagramLogin = false
    @Published private(set) var previewResolution: MediaResolution?
    @Published var selectedPreviewAssetIDs: Set<UUID> = []
    @Published var isShowingPreview = false
    @Published private(set) var isPreparingPreview = false
    @Published private(set) var previewError: String?
    @Published var profileUsername = ""
    @Published private(set) var profilePosts: [InstagramProfilePost] = []
    @Published var selectedProfilePostIDs: Set<String> = []
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var profileError: String?
    @Published private(set) var favoriteProfiles: [FavoriteProfile] = FavoriteProfileStore.load()
    @Published private(set) var lastProfileNewContentCount = 0

    private let resolver = InstagramMediaResolver()
    private let webStoryResolver = InstagramWebStoryResolver()
    private let profileFeedResolver = InstagramProfileFeedResolver()
    private let downloader = MediaDownloader()
    private let saver = PhotoLibrarySaver()
    private let thumbnailGenerator = ThumbnailGenerator()
    private var queueWorker: Task<Void, Never>?
    private var preparedResolutions: [UUID: MediaResolution] = [:]

    init() {
        AppPreferences.registerDefaults()
    }

    var canStart: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPreparingPreview
    }

    var canFetchProfile: Bool {
        !profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isLoadingProfile
    }

    var canSaveSelectedProfilePosts: Bool {
        !selectedProfilePostIDs.isEmpty && !isLoadingProfile
    }

    var profileRegularPosts: [InstagramProfilePost] {
        profilePosts.filter { $0.contentKind == .post }
    }

    var profileReels: [InstagramProfilePost] {
        profilePosts.filter { $0.contentKind == .reel }
    }

    var profileStories: [InstagramProfilePost] {
        profilePosts.filter { $0.contentKind == .story }
    }

    var isCurrentProfileFavorite: Bool {
        guard let username = normalizedProfileUsername(profileUsername) else { return false }
        return favoriteProfiles.contains { $0.username.caseInsensitiveCompare(username) == .orderedSame }
    }

    func pasteFromClipboard() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string {
            inputText = text
        }
        #endif
    }

    func start() {
        let input = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !input.isEmpty else {
            return
        }

        if !AppPreferences.previewsBeforeSaving {
            inputText = ""
            enqueue(input: input)
            return
        }

        isPreparingPreview = true
        previewError = nil

        Task {
            do {
                let resolution = try await resolveMedia(input)
                previewResolution = resolution
                selectedPreviewAssetIDs = Set(resolution.assets.map(\.id))
                isShowingPreview = true
                inputText = ""
            } catch {
                previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isPreparingPreview = false
        }
    }

    func togglePreviewAsset(_ asset: MediaAsset) {
        if selectedPreviewAssetIDs.contains(asset.id) {
            selectedPreviewAssetIDs.remove(asset.id)
        } else {
            selectedPreviewAssetIDs.insert(asset.id)
        }
        HapticFeedback.selection()
    }

    func confirmPreviewSave() {
        guard let resolution = previewResolution else {
            return
        }

        let assets = resolution.assets.filter { selectedPreviewAssetIDs.contains($0.id) }
        guard !assets.isEmpty else {
            return
        }

        let selectedResolution = MediaResolution(
            assets: assets,
            username: resolution.username,
            contentKind: resolution.contentKind,
            sourceURL: resolution.sourceURL
        )
        enqueue(input: resolution.sourceURL.absoluteString, preparedResolution: selectedResolution)
        dismissPreview()
    }

    func dismissPreview() {
        isShowingPreview = false
        previewResolution = nil
        selectedPreviewAssetIDs = []
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard
            url.scheme?.lowercased() == "igsave",
            url.host(percentEncoded: false)?.lowercased() == "import",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let importedURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
            !importedURL.isEmpty
        else {
            return false
        }

        enqueue(input: importedURL)
        return true
    }

    func fetchLatestProfilePosts() {
        let username = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !isLoadingProfile else {
            return
        }

        isLoadingProfile = true
        profileError = nil
        profilePosts = []
        selectedProfilePostIDs = []

        Task {
            do {
                let posts = try await profileFeedResolver.latestPosts(for: username, limitPerKind: 5)
                profilePosts = posts
                updateFavoriteSnapshot(for: username, posts: posts)
            } catch {
                profileError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

            isLoadingProfile = false
        }
    }

    func toggleCurrentProfileFavorite() {
        guard let username = normalizedProfileUsername(profileUsername) else {
            return
        }

        if let index = favoriteProfiles.firstIndex(where: {
            $0.username.caseInsensitiveCompare(username) == .orderedSame
        }) {
            favoriteProfiles.remove(at: index)
        } else {
            favoriteProfiles.append(FavoriteProfile(
                username: username,
                lastKnownPostIDs: Set(profilePosts.map(\.id))
            ))
        }
        FavoriteProfileStore.persist(favoriteProfiles)
        HapticFeedback.selection()
    }

    func selectFavoriteProfile(_ favorite: FavoriteProfile) {
        profileUsername = favorite.username
        fetchLatestProfilePosts()
    }

    func removeFavoriteProfile(_ favorite: FavoriteProfile) {
        favoriteProfiles.removeAll { $0.id == favorite.id }
        FavoriteProfileStore.persist(favoriteProfiles)
    }

    func toggleProfilePost(_ post: InstagramProfilePost) {
        if selectedProfilePostIDs.contains(post.id) {
            selectedProfilePostIDs.remove(post.id)
        } else {
            selectedProfilePostIDs.insert(post.id)
        }
        HapticFeedback.selection()
    }

    func toggleAllProfilePosts(in posts: [InstagramProfilePost]) {
        let postIDs = Set(posts.map(\.id))

        guard !postIDs.isEmpty else {
            return
        }

        if postIDs.isSubset(of: selectedProfilePostIDs) {
            selectedProfilePostIDs.subtract(postIDs)
        } else {
            selectedProfilePostIDs.formUnion(postIDs)
        }
        HapticFeedback.selection()
    }

    func saveSelectedProfilePosts() {
        let selectedPosts = profilePosts
            .filter { selectedProfilePostIDs.contains($0.id) }

        guard !selectedPosts.isEmpty else {
            return
        }

        let batchID = selectedPosts.count > 1 ? UUID() : nil
        for post in selectedPosts {
            enqueue(input: post.url.absoluteString, batchID: batchID)
        }

        selectedProfilePostIDs = []
        HapticFeedback.selection()
    }

    func showInstagramLogin() {
        isShowingInstagramLogin = true
    }

    func finishInstagramLogin() {
        isShowingInstagramLogin = false

        Task {
            await refreshInstagramSessionStatus()
        }
    }

    func refreshInstagramSessionStatus() async {
        instagramSessionState = await InstagramSessionStore.validatedSessionState()
        hasInstagramSession = instagramSessionState.isConnected
    }

    func logoutInstagram() {
        Task {
            await InstagramSessionStore.clearInstagramSession()
            await refreshInstagramSessionStatus()
        }
    }

    func saveAgain(_ save: RecentSave) {
        enqueue(input: save.sourceURL, allowsDuplicate: true)
    }

    func deleteRecentSave(_ save: RecentSave) {
        recentSaves = RecentSaveStore.remove(save, from: recentSaves)
        HapticFeedback.selection()
    }

    func clearRecentSaves() {
        recentSaves = RecentSaveStore.removeAll(from: recentSaves)
    }

    func copyRecentLink(_ save: RecentSave) {
        #if canImport(UIKit)
        UIPasteboard.general.string = save.sourceURL
        #endif
    }

    func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    func resumePendingJobs() {
        MediaDownloader.cleanCache()
        removeSupersededTerminalJobs()
        consumePendingImports()
        ensureQueueProcessing()
    }

    func consumePendingImports() {
        for link in PendingImportStore.consumeAll() {
            enqueue(input: link)
        }
    }

    func retry(_ job: SaveJob, allowDuplicate: Bool = false) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            return
        }

        jobs[index].prepareForRetry(forceDuplicate: allowDuplicate)
        persistJobs()
        ensureQueueProcessing()
        HapticFeedback.selection()
    }

    func cancel(_ job: SaveJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            return
        }

        if jobs[index].status.isRunning {
            jobs[index].status = .cancelling
            jobs[index].updatedAt = Date()
            persistJobs()
            queueWorker?.cancel()
        } else {
            jobs[index].status = .cancelled
            jobs[index].attemptID = nil
            jobs[index].updatedAt = Date()
            persistJobs()
        }
        isWorking = jobs.contains { $0.status.isRunning }
    }

    func cancelBatch(containing job: SaveJob) {
        guard let batchID = job.batchID else {
            cancel(job)
            return
        }

        let hasRunningJob = jobs.contains { $0.batchID == batchID && $0.status.isRunning }

        for index in jobs.indices where jobs[index].batchID == batchID && !jobs[index].status.isTerminal {
            if jobs[index].status.isRunning {
                jobs[index].status = .cancelling
            } else {
                jobs[index].status = .cancelled
                jobs[index].attemptID = nil
            }
            jobs[index].updatedAt = Date()
        }
        if hasRunningJob {
            queueWorker?.cancel()
        }
        persistJobs()
        HapticFeedback.warning()

        Task {
            await Task.yield()
            ensureQueueProcessing()
        }
    }

    func remove(_ job: SaveJob) {
        guard !job.status.isRunning else {
            return
        }

        jobs.removeAll { $0.id == job.id }
        persistJobs()
    }

    func clearFinishedJobs() {
        jobs.removeAll { $0.status.isTerminal }
        persistJobs()
    }

    private func enqueue(
        input: String,
        allowsDuplicate: Bool = false,
        preparedResolution: MediaResolution? = nil,
        batchID: UUID? = nil
    ) {
        let job = SaveJob(input: input, allowsDuplicate: allowsDuplicate, batchID: batchID)
        jobs.insert(job, at: 0)
        if let preparedResolution {
            preparedResolutions[job.id] = preparedResolution
        }
        persistJobs()
        ensureQueueProcessing()
        HapticFeedback.selection()
    }

    private func ensureQueueProcessing() {
        guard queueWorker == nil, jobs.contains(where: { $0.status == .queued }) else {
            return
        }

        queueWorker = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        isWorking = true
        var processedJobIDs: Set<UUID> = []

        while !Task.isCancelled,
              let job = jobs
                .filter({ $0.status == .queued })
                .min(by: { $0.createdAt < $1.createdAt }) {
            await run(jobID: job.id)
            processedJobIDs.insert(job.id)
        }

        if !Task.isCancelled {
            let processedJobs = jobs.filter { processedJobIDs.contains($0.id) }
            let successCount = processedJobs.filter { job in
                switch job.status {
                case .saved, .partiallySaved: true
                default: false
                }
            }.count
            let partialCount = processedJobs.filter {
                if case .partiallySaved = $0.status { return true }
                return false
            }.count
            let failureCount = processedJobs.filter {
                switch $0.status {
                case .failed, .duplicate: true
                default: false
                }
            }.count
            await NotificationService.notifySaveCompletion(
                successCount: successCount,
                partialCount: partialCount,
                failureCount: failureCount
            )

            try? await Task.sleep(for: .seconds(2))
            jobs.removeAll { job in
                guard processedJobIDs.contains(job.id) else { return false }
                if case .saved = job.status { return true }
                return false
            }
            persistJobs()
        }

        queueWorker = nil
        isWorking = jobs.contains { $0.status.isRunning }

        if jobs.contains(where: { $0.status == .queued }) {
            ensureQueueProcessing()
        }
    }

    private func run(jobID: UUID) async {
        guard let attemptID = beginAttempt(for: jobID),
              let initialJob = jobs.first(where: { $0.id == jobID }) else {
            return
        }

        let input = initialJob.input

        do {
            try Task.checkCancellation()
            let resolution: MediaResolution
            if let pendingAssets = initialJob.pendingAssets {
                let assets = pendingAssets.compactMap(\.asset)
                guard assets.count == pendingAssets.count else {
                    throw SaveJobError.invalidRestoredAsset
                }
                let sourceURL = firstURL(in: input) ?? assets.first?.sourceURL
                guard let sourceURL else {
                    throw SaveJobError.invalidRestoredAsset
                }
                resolution = MediaResolution(
                    assets: assets,
                    username: initialJob.username,
                    contentKind: initialJob.contentKind ?? .unknown,
                    sourceURL: sourceURL
                )
            } else if let preparedResolution = preparedResolutions.removeValue(forKey: jobID) {
                resolution = preparedResolution
            } else {
                resolution = try await resolveMedia(input)
            }

            updateMetadata(jobID, resolution: resolution, attemptID: attemptID)
            prepareAssets(jobID, resolution: resolution, attemptID: attemptID)

            if AppPreferences.protectsAgainstDuplicates,
               !initialJob.allowsDuplicate,
               (initialJob.successfulAssetCount ?? 0) == 0,
               let previousSave = RecentSaveStore.previousSave(for: resolution.sourceURL.absoluteString) {
                update(jobID, status: .duplicate(previousSavedAt: previousSave.savedAt), attemptID: attemptID)
                HapticFeedback.warning()
                return
            }

            let assets = resolution.assets
            if assets.isEmpty {
                finalize(jobID, attemptID: attemptID)
                return
            }

            for (offset, asset) in assets.enumerated() {
                try Task.checkCancellation()
                let current = offset + 1
                update(
                    jobID,
                    status: .downloading(current: current, total: assets.count),
                    attemptID: attemptID
                )

                do {
                    let fileURL = try await downloader.download(
                        asset,
                        allowsCellularAccess: AppPreferences.allowsCellularDownloads
                    )

                    update(
                        jobID,
                        status: .saving(current: current, total: assets.count),
                        attemptID: attemptID
                    )
                    try await saver.save(
                        fileURL: fileURL,
                        kind: asset.kind,
                        albumName: AppPreferences.usesDedicatedAlbum ? AppPreferences.dedicatedAlbumName : nil
                    )

                    await recordAssetSuccess(
                        jobID,
                        attemptID: attemptID,
                        asset: asset,
                        fileURL: fileURL,
                        input: input,
                        resolution: resolution
                    )
                    try Task.checkCancellation()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    recordAssetFailure(
                        jobID,
                        attemptID: attemptID,
                        asset: asset,
                        message: errorMessage(for: error)
                    )
                }
            }

            finalize(jobID, attemptID: attemptID)
            MediaDownloader.cleanCache()
        } catch is CancellationError {
            update(jobID, status: .cancelled, attemptID: attemptID)
        } catch {
            let message = errorMessage(for: error)
            setAttemptError(jobID, attemptID: attemptID, message: message)
            finalize(jobID, attemptID: attemptID, fallbackError: message)
        }
    }

    private func resolveMedia(_ input: String) async throws -> MediaResolution {
        guard isStoryInput(input) else {
            return try await resolver.resolve(input)
        }

        await refreshInstagramSessionStatus()

        guard hasInstagramSession else {
            throw MediaResolverError.storyLoginRequired
        }

        return try await webStoryResolver.resolve(input)
    }

    private func beginAttempt(for id: UUID) -> UUID? {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let attemptID = UUID()
        jobs[index].attemptID = attemptID
        jobs[index].status = .resolving
        jobs[index].updatedAt = Date()
        persistJobs()
        return attemptID
    }

    private func update(_ id: UUID, status: SaveStatus, attemptID: UUID? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              attemptID == nil || jobs[index].attemptID == attemptID else {
            return
        }

        jobs[index].status = status
        jobs[index].updatedAt = Date()
        persistJobs()
    }

    private func updateMetadata(_ id: UUID, resolution: MediaResolution, attemptID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].attemptID == attemptID else {
            return
        }

        jobs[index].username = resolution.username
        jobs[index].contentKind = resolution.contentKind
        let expectedItemCount = (jobs[index].successfulAssetCount ?? 0) + resolution.assets.count
        jobs[index].itemCount = max(jobs[index].itemCount ?? 0, expectedItemCount)
        jobs[index].previewURLString = resolution.assets.first?.sourceURL.absoluteString
        jobs[index].updatedAt = Date()
        persistJobs()
    }

    private func prepareAssets(_ id: UUID, resolution: MediaResolution, attemptID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].attemptID == attemptID else {
            return
        }

        if jobs[index].pendingAssets == nil {
            jobs[index].pendingAssets = resolution.assets.map(SaveAssetDescriptor.init)
            jobs[index].failedAssets = []
            jobs[index].successfulAssetCount = jobs[index].successfulAssetCount ?? 0
            jobs[index].failedAssetCount = 0
            jobs[index].lastErrorMessage = nil
        }
        jobs[index].updatedAt = Date()
        persistJobs()
    }

    private func recordAssetFailure(
        _ id: UUID,
        attemptID: UUID,
        asset: MediaAsset,
        message: String
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].attemptID == attemptID else {
            return
        }

        let descriptor = SaveAssetDescriptor(asset: asset)
        jobs[index].pendingAssets?.removeFirst(descriptor)
        jobs[index].failedAssets = (jobs[index].failedAssets ?? []) + [descriptor]
        jobs[index].failedAssetCount = (jobs[index].failedAssetCount ?? 0) + 1
        jobs[index].lastErrorMessage = message
        jobs[index].updatedAt = Date()
        persistJobs()
    }

    private func recordAssetSuccess(
        _ id: UUID,
        attemptID: UUID,
        asset: MediaAsset,
        fileURL: URL,
        input: String,
        resolution: MediaResolution
    ) async {
        guard let initialIndex = jobs.firstIndex(where: { $0.id == id }),
              jobs[initialIndex].attemptID == attemptID else {
            return
        }

        let recentSaveID = jobs[initialIndex].recentSaveID ?? UUID()
        let existingSave = recentSaves.first(where: { $0.id == recentSaveID })
        let previewFilename: String?
        if let existingPreview = existingSave?.previewFilename {
            previewFilename = existingPreview
        } else {
            previewFilename = await thumbnailGenerator.makeThumbnail(for: fileURL, kind: asset.kind)
        }

        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].attemptID == attemptID else {
            return
        }

        let savedCount = (jobs[index].successfulAssetCount ?? 0) + 1
        jobs[index].pendingAssets?.removeFirst(SaveAssetDescriptor(asset: asset))
        jobs[index].successfulAssetCount = savedCount
        jobs[index].recentSaveID = recentSaveID
        jobs[index].updatedAt = Date()

        let save = RecentSave(
            id: recentSaveID,
            username: displayUsername(from: resolution, input: input),
            savedAt: existingSave?.savedAt ?? Date(),
            itemCount: savedCount,
            contentKind: resolution.contentKind,
            sourceURL: resolution.sourceURL.absoluteString,
            previewFilename: previewFilename
        )
        recentSaves = RecentSaveStore.upsert(save, in: recentSaves)
        persistJobs()
    }

    private func setAttemptError(_ id: UUID, attemptID: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].attemptID == attemptID else {
            return
        }

        jobs[index].lastErrorMessage = message
        jobs[index].updatedAt = Date()
        persistJobs()
    }

    private func finalize(_ id: UUID, attemptID: UUID, fallbackError: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].attemptID == attemptID else {
            return
        }

        let savedCount = jobs[index].successfulAssetCount ?? 0
        let recordedFailureCount = jobs[index].failedAssetCount ?? 0
        let unresolvedCount = jobs[index].pendingAssets?.count ?? 0
        let failureCount = max(recordedFailureCount, unresolvedCount)
        let message = jobs[index].lastErrorMessage ?? fallbackError ?? "部分内容未能保存，请重试。"

        let terminalStatus = SaveCompletion.status(
            saved: savedCount,
            failed: failureCount,
            message: message
        )
        jobs[index].status = terminalStatus

        switch terminalStatus {
        case .saved:
            jobs[index].failedAssets = []
            jobs[index].lastErrorMessage = nil
            HapticFeedback.success()
        case .partiallySaved:
            HapticFeedback.warning()
        case .failed:
            HapticFeedback.warning()
        case .idle, .queued, .resolving, .downloading, .saving, .cancelling, .duplicate, .cancelled:
            break
        }
        jobs[index].updatedAt = Date()
        persistJobs()
        removeSupersededTerminalJobs(keeping: id)
    }

    private func errorMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func persistJobs() {
        SaveJobStore.persist(jobs)
    }

    private func removeSupersededTerminalJobs(keeping jobID: UUID? = nil) {
        let previousCount = jobs.count

        jobs.removeAll { job in
            guard job.id != jobID else { return false }

            switch job.status {
            case .failed, .cancelled, .duplicate:
                let jobSource = normalizedSource(job.input)
                return recentSaves.contains { save in
                    save.savedAt >= job.createdAt && normalizedSource(save.sourceURL) == jobSource
                }
            case .partiallySaved:
                let jobSource = normalizedSource(job.input)
                return recentSaves.contains { save in
                    save.id != job.recentSaveID &&
                        save.savedAt >= job.createdAt &&
                        save.itemCount >= (job.itemCount ?? .max) &&
                        normalizedSource(save.sourceURL) == jobSource
                }
            case .idle, .queued, .resolving, .downloading, .saving, .cancelling, .saved:
                return false
            }
        }

        if jobs.count != previousCount {
            persistJobs()
        }
    }

    private func normalizedSource(_ rawValue: String) -> String {
        guard let url = firstURL(in: rawValue),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        components.query = nil
        components.fragment = nil
        components.host = components.host?.lowercased()
        var value = components.string?.lowercased() ?? url.absoluteString.lowercased()
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func displayUsername(from resolution: MediaResolution, input: String) -> String {
        if let username = resolution.username, !username.isEmpty {
            return "@\(username)"
        }

        guard
            let url = URL(string: input),
            let host = url.host(percentEncoded: false)
        else {
            return "Instagram"
        }

        if host.contains("instagram.com") {
            return "Instagram"
        }

        return host
    }

    private func isStoryInput(_ input: String) -> Bool {
        guard let url = firstURL(in: input) else {
            return input.contains("/stories/")
        }

        return url.pathComponents.contains { $0.caseInsensitiveCompare("stories") == .orderedSame }
    }

    private func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return detector?
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first
    }

    private func normalizedProfileUsername(_ rawValue: String) -> String? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !value.isEmpty else { return nil }
        return value.lowercased()
    }

    private func updateFavoriteSnapshot(for rawUsername: String, posts: [InstagramProfilePost]) {
        guard
            let username = normalizedProfileUsername(rawUsername),
            let index = favoriteProfiles.firstIndex(where: {
                $0.username.caseInsensitiveCompare(username) == .orderedSame
            })
        else {
            lastProfileNewContentCount = 0
            return
        }

        let currentIDs = Set(posts.filter { $0.contentKind != .story }.map(\.id))
        let previousIDs = favoriteProfiles[index].lastKnownPostIDs
        lastProfileNewContentCount = previousIDs.isEmpty ? 0 : currentIDs.subtracting(previousIDs).count
        favoriteProfiles[index].lastKnownPostIDs = currentIDs
        FavoriteProfileStore.persist(favoriteProfiles)
    }
}

private enum SaveJobError: LocalizedError {
    case invalidRestoredAsset

    var errorDescription: String? {
        switch self {
        case .invalidRestoredAsset:
            "保存任务中的媒体地址已失效，请重新添加原链接。"
        }
    }
}

private extension Array where Element: Equatable {
    mutating func removeFirst(_ element: Element) {
        guard let index = firstIndex(of: element) else { return }
        remove(at: index)
    }
}
