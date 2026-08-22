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
    @Published private(set) var jobs: [SaveJob] = []
    @Published private(set) var isWorking = false
    @Published private(set) var recentSaves: [RecentSave] = RecentSaveStore.load()
    @Published private(set) var hasInstagramSession = false
    @Published var isShowingInstagramLogin = false
    @Published var profileUsername = ""
    @Published private(set) var profilePosts: [InstagramProfilePost] = []
    @Published var selectedProfilePostIDs: Set<String> = []
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var profileError: String?

    private let resolver = InstagramMediaResolver()
    private let webStoryResolver = InstagramWebStoryResolver()
    private let profileFeedResolver = InstagramProfileFeedResolver()
    private let downloader = MediaDownloader()
    private let saver = PhotoLibrarySaver()
    private let thumbnailGenerator = ThumbnailGenerator()

    var canStart: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var canFetchProfile: Bool {
        !profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isLoadingProfile &&
            !isWorking
    }

    var canSaveSelectedProfilePosts: Bool {
        !selectedProfilePostIDs.isEmpty && !isWorking && !isLoadingProfile
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

    func pasteFromClipboard() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string {
            inputText = text
        }
        #endif
    }

    func start() {
        let input = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !input.isEmpty, !isWorking else {
            return
        }

        isWorking = true
        inputText = ""

        Task {
            await run(input: input)
            isWorking = false
        }
    }

    func fetchLatestProfilePosts() {
        let username = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !isLoadingProfile, !isWorking else {
            return
        }

        isLoadingProfile = true
        profileError = nil
        profilePosts = []
        selectedProfilePostIDs = []

        Task {
            do {
                profilePosts = try await profileFeedResolver.latestPosts(for: username, limitPerKind: 5)
            } catch {
                profileError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

            isLoadingProfile = false
        }
    }

    func toggleProfilePost(_ post: InstagramProfilePost) {
        if selectedProfilePostIDs.contains(post.id) {
            selectedProfilePostIDs.remove(post.id)
        } else {
            selectedProfilePostIDs.insert(post.id)
        }
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
    }

    func saveSelectedProfilePosts() {
        let selectedPosts = profilePosts
            .filter { selectedProfilePostIDs.contains($0.id) }

        guard !selectedPosts.isEmpty, !isWorking else {
            return
        }

        isWorking = true

        Task {
            for post in selectedPosts {
                if post.contentKind == .story,
                   let directMediaURL = post.directMediaURL,
                   let mediaKind = post.mediaKind {
                    await run(
                        input: post.url.absoluteString,
                        preResolved: storyResolution(
                            for: post,
                            mediaURL: directMediaURL,
                            mediaKind: mediaKind
                        )
                    )
                } else {
                    await run(input: post.url.absoluteString)
                }
            }

            isWorking = false
        }
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
        hasInstagramSession = await InstagramSessionStore.hasActiveSession()
    }

    private func run(input: String, preResolved: MediaResolution? = nil) async {
        let job = SaveJob(input: input, status: .resolving)
        jobs.insert(job, at: 0)

        do {
            let resolution: MediaResolution
            if let preResolved {
                resolution = preResolved
            } else {
                resolution = try await resolveMedia(input)
            }
            let assets = resolution.assets
            var savedCount = 0
            var downloadedMedia: [DownloadedMedia] = []

            for (offset, asset) in assets.enumerated() {
                let current = offset + 1
                update(job.id, status: .downloading(current: current, total: assets.count))

                let fileURL = try await downloader.download(asset)
                downloadedMedia.append(DownloadedMedia(fileURL: fileURL, kind: asset.kind))

                update(job.id, status: .saving(current: current, total: assets.count))
                try await saver.save(fileURL: fileURL, kind: asset.kind)

                savedCount += 1
            }

            addRecentSave(input: input, resolution: resolution, downloadedMedia: downloadedMedia, savedCount: savedCount)
            update(job.id, status: .saved(count: savedCount))
        } catch {
            update(job.id, status: .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
        }

    }

    private func storyResolution(
        for post: InstagramProfilePost,
        mediaURL: URL,
        mediaKind: MediaKind
    ) -> MediaResolution {
        let fileExtension: String
        switch mediaKind {
        case .image:
            fileExtension = "jpg"
        case .video:
            fileExtension = "mp4"
        case .unknown:
            fileExtension = mediaURL.pathExtension.isEmpty ? "dat" : mediaURL.pathExtension
        }

        let username = storyUsername(from: post.url)
        let asset = MediaAsset(
            sourceURL: mediaURL,
            kind: mediaKind,
            suggestedFilename: "ig-story-\(post.id.replacingOccurrences(of: "story-", with: "")).\(fileExtension)"
        )

        return MediaResolution(
            assets: [asset],
            username: username,
            contentKind: .story,
            sourceURL: post.url
        )
    }

    private func storyUsername(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }

        guard
            let storyIndex = components.firstIndex(of: "stories"),
            components.indices.contains(storyIndex + 1)
        else {
            return nil
        }

        return components[storyIndex + 1]
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

    private func update(_ id: UUID, status: SaveStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        jobs[index].status = status
    }

    private func addRecentSave(
        input: String,
        resolution: MediaResolution,
        downloadedMedia: [DownloadedMedia],
        savedCount: Int
    ) {
        guard savedCount > 0 else {
            return
        }

        let previewSource = downloadedMedia.first(where: { $0.kind == .image }) ?? downloadedMedia.first
        let previewFilename = previewSource.flatMap {
            thumbnailGenerator.makeThumbnail(for: $0.fileURL, kind: $0.kind)
        }
        let save = RecentSave(
            username: displayUsername(from: resolution, input: input),
            itemCount: savedCount,
            contentKind: resolution.contentKind,
            sourceURL: resolution.sourceURL.absoluteString,
            previewFilename: previewFilename
        )

        recentSaves = RecentSaveStore.add(save, to: recentSaves)
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
        guard let url = URL(string: input) else {
            return input.contains("/stories/")
        }

        return url.pathComponents.contains("stories")
    }
}

private struct DownloadedMedia {
    let fileURL: URL
    let kind: MediaKind
}
