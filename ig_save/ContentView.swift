//
//  ContentView.swift
//  ig_save
//
//  Created by yank on 2026/5/4.
//

import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = DownloadViewModel()
    @State private var selectedTab: AppTab = .save
    @State private var inputMode: SaveInputMode = .link
    @State private var profileContentFilter: ProfileContentFilter = .post
    @State private var recentContentFilter: RecentContentFilter = .all
    @State private var recentSearchText = ""
    @State private var isShowingSettings = false
    @State private var selectedRecentSave: RecentSave?
    @FocusState private var isInputFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("保存", systemImage: "square.and.arrow.down", value: AppTab.save) {
                saveNavigation
            }

            Tab("最近", systemImage: "clock.arrow.circlepath", value: AppTab.recents) {
                recentsNavigation
            }
        }
        .tint(Brand.accent)
        .tabBarMinimizeBehavior(.never)
        .onOpenURL { url in
            if viewModel.handleIncomingURL(url) {
                selectedTab = .save
                inputMode = .link
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .igSavePendingImport)) { _ in
            viewModel.consumePendingImports()
            selectedTab = .save
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.consumePendingImports()
            }
        }
        .task {
            await viewModel.refreshInstagramSessionStatus()
            viewModel.resumePendingJobs()
        }
        .sheet(
            isPresented: $viewModel.isShowingInstagramLogin,
            onDismiss: {
                Task {
                    await viewModel.refreshInstagramSessionStatus()
                }
            }
        ) {
            InstagramLoginView {
                viewModel.finishInstagramLogin()
            }
        }
        .sheet(isPresented: $viewModel.isShowingPreview, onDismiss: viewModel.dismissPreview) {
            if let resolution = viewModel.previewResolution {
                MediaPreviewView(
                    resolution: resolution,
                    selectedAssetIDs: viewModel.selectedPreviewAssetIDs,
                    onToggle: viewModel.togglePreviewAsset,
                    onCancel: viewModel.dismissPreview,
                    onConfirm: viewModel.confirmPreviewSave
                )
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                sessionState: viewModel.instagramSessionState,
                onLogin: {
                    isShowingSettings = false
                    Task { @MainActor in
                        await Task.yield()
                        viewModel.showInstagramLogin()
                    }
                },
                onLogout: viewModel.logoutInstagram,
                onOpenSettings: viewModel.openAppSettings
            )
        }
        .sheet(item: $selectedRecentSave) { save in
            RecentSaveDetailView(
                save: save,
                onOpen: {
                    if let url = URL(string: save.sourceURL) { openURL(url) }
                },
                onCopy: { viewModel.copyRecentLink(save) },
                onSaveAgain: {
                    viewModel.saveAgain(save)
                    selectedRecentSave = nil
                },
                onDelete: {
                    viewModel.deleteRecentSave(save)
                    selectedRecentSave = nil
                }
            )
        }
    }

    private var saveNavigation: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 24) {
                        linkComposer
                        profilePostsSection
                        taskQueueSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("IGSave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")

                    Button {
                        viewModel.showInstagramLogin()
                    } label: {
                        Image(systemName: viewModel.hasInstagramSession ? "checkmark.circle.fill" : "person.crop.circle")
                    }
                    .accessibilityLabel(viewModel.hasInstagramSession ? "Instagram 已登录" : "登录 Instagram")
                }
            }
        }
    }

    private var recentsNavigation: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                if filteredRecentSaves.isEmpty && recentSearchText.isEmpty && recentContentFilter == .all {
                    ContentUnavailableView(
                        "还没有保存记录",
                        systemImage: "photo.stack",
                        description: Text("保存成功的帖子、Reel 和快拍会显示在这里。")
                    )
                } else {
                    VStack(spacing: 12) {
                        Picker("内容类型", selection: $recentContentFilter) {
                            ForEach(RecentContentFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        if filteredRecentSaves.isEmpty {
                            ContentUnavailableView(
                                "没有匹配的记录",
                                systemImage: "magnifyingglass",
                                description: Text("试试其他账号名称或内容类型。")
                            )
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                                    ForEach(groupedRecentSaves) { group in
                                        Section {
                                            ForEach(group.saves) { save in
                                                RecentSaveRow(
                                                    save: save,
                                                    onSelect: { selectedRecentSave = save },
                                                    onOpen: {
                                                        if let url = URL(string: save.sourceURL) { openURL(url) }
                                                    },
                                                    onCopy: { viewModel.copyRecentLink(save) },
                                                    onSaveAgain: { viewModel.saveAgain(save) },
                                                    onDelete: { viewModel.deleteRecentSave(save) }
                                                )
                                            }
                                        } header: {
                                            Text(group.title)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.secondary)
                                                .textCase(.uppercase)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 6)
                                                .background(Color(uiColor: .systemGroupedBackground).opacity(0.94))
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 36)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("最近保存")
            .navigationBarTitleDisplayMode(.large)
            .recentSearchable(
                enabled: viewModel.recentSaves.count >= 8,
                text: $recentSearchText
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清空全部记录", role: .destructive) {
                            viewModel.clearRecentSaves()
                        }
                    } label: {
                        Text("\(viewModel.recentSaves.count)")
                            .font(.caption.weight(.semibold))
                    }
                    .disabled(viewModel.recentSaves.isEmpty)
                }
            }
        }
    }

    private var filteredRecentSaves: [RecentSave] {
        let query = recentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.recentSaves.filter { save in
            let matchesKind = recentContentFilter.matches(save.contentKind)
            let matchesQuery = query.isEmpty ||
                save.username.lowercased().contains(query) ||
                save.sourceURL.lowercased().contains(query)
            return matchesKind && matchesQuery
        }
    }

    private var groupedRecentSaves: [RecentSaveGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRecentSaves) { save -> String in
            if calendar.isDateInToday(save.savedAt) { return "今天" }
            if calendar.isDateInYesterday(save.savedAt) { return "昨天" }
            return "更早"
        }
        let order = ["今天", "昨天", "更早"]
        return order.compactMap { title in
            guard let saves = grouped[title], !saves.isEmpty else { return nil }
            return RecentSaveGroup(title: title, saves: saves)
        }
    }

    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("保存方式", selection: $inputMode) {
                Label("链接", systemImage: "link")
                    .tag(SaveInputMode.link)
                Label("账号", systemImage: "person.crop.square")
                    .tag(SaveInputMode.profile)
            }
            .pickerStyle(.segmented)

            instagramSessionRow

            if inputMode == .link {
                linkInput
            } else {
                profileInput
            }
        }
        .padding(20)
        .surfaceCard(radius: 26)
        .animation(.snappy, value: inputMode)
    }

    private var instagramSessionRow: some View {
        Button {
            viewModel.showInstagramLogin()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: viewModel.hasInstagramSession ? "checkmark.shield.fill" : "person.badge.key")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(viewModel.hasInstagramSession ? Color.green : Brand.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.hasInstagramSession ? "Instagram 已连接" : "连接 Instagram")
                        .font(.subheadline.weight(.semibold))

                    Text(instagramSessionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var instagramSessionSubtitle: String {
        switch viewModel.instagramSessionState {
        case let .connected(username):
            if let username, !username.isEmpty {
                return "已登录 @\(username)"
            }
            return "可以读取当前账号有权访问的内容"
        case .expired:
            return "登录已过期，请重新连接"
        case .disconnected:
            return "账号获取和快拍需要登录"
        }
    }

    private var linkInput: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("内容链接")
                    .font(.headline)

                Text("支持 Instagram 帖子、Reel、快拍和媒体直链")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .padding(.top, 3)

                TextField("粘贴链接…", text: $viewModel.inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .lineLimit(2...4)
                    .font(.body)
            }
            .padding(16)
            .frame(minHeight: 58, alignment: .top)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let previewError = viewModel.previewError {
                Label(previewError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        viewModel.pasteFromClipboard()
                        isInputFocused = true
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 86, height: 48)
                    }
                    .buttonStyle(.glass)

                    Button {
                        isInputFocused = false
                        viewModel.start()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isPreparingPreview {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                            }
                            Text(viewModel.isPreparingPreview ? "正在解析" : "解析并保存")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.accent)
                    .disabled(!viewModel.canStart)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var profileInput: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("指定账号")
                    .font(.headline)

                Text("获取最新帖子、Reels，以及当前仍有效的快拍")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("@")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.accent)

                TextField("用户名", text: $viewModel.profileUsername)
                    .focused($isInputFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.search)
                    .onSubmit {
                        viewModel.fetchLatestProfilePosts()
                    }

                Button {
                    viewModel.toggleCurrentProfileFavorite()
                } label: {
                    Image(systemName: viewModel.isCurrentProfileFavorite ? "star.fill" : "star")
                        .foregroundStyle(viewModel.isCurrentProfileFavorite ? .yellow : Brand.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(viewModel.isCurrentProfileFavorite ? "取消收藏账号" : "收藏账号")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !viewModel.favoriteProfiles.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(viewModel.favoriteProfiles) { favorite in
                            Button {
                                isInputFocused = false
                                viewModel.selectFavoriteProfile(favorite)
                            } label: {
                                Label("@\(favorite.username)", systemImage: "star.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Brand.accent.opacity(0.09), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("移除收藏", systemImage: "star.slash", role: .destructive) {
                                    viewModel.removeFavoriteProfile(favorite)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if viewModel.lastProfileNewContentCount > 0 {
                Label("相比上次新增 \(viewModel.lastProfileNewContentCount) 项内容", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.accent)
            }

            if let profileError = viewModel.profileError {
                Label(profileError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                isInputFocused = false
                profileContentFilter = .post
                viewModel.fetchLatestProfilePosts()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoadingProfile {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }

                    Text(viewModel.isLoadingProfile ? "正在获取" : "获取主页内容")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.accent)
            .disabled(!viewModel.canFetchProfile)
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    @ViewBuilder
    private var profilePostsSection: some View {
        if inputMode == .profile, !viewModel.profilePosts.isEmpty {
            let visiblePosts = profilePosts(for: profileContentFilter)
            let visibleIDs = Set(visiblePosts.map(\.id))
            let allVisibleSelected = !visibleIDs.isEmpty && visibleIDs.isSubset(of: viewModel.selectedProfilePostIDs)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择要保存的内容")
                        .font(.title3.weight(.bold))

                    Text("帖子与 Reels 分开显示，选择后可一次保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("内容类型", selection: $profileContentFilter) {
                    Text("帖子  \(viewModel.profileRegularPosts.count)")
                        .tag(ProfileContentFilter.post)
                    Text("Reels  \(viewModel.profileReels.count)")
                        .tag(ProfileContentFilter.reel)
                    Text("快拍  \(viewModel.profileStories.count)")
                        .tag(ProfileContentFilter.story)
                }
                .pickerStyle(.segmented)

                HStack {
                    Label(
                        profileContentFilter.title,
                        systemImage: profileContentFilter.iconName
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button(allVisibleSelected ? "取消本栏" : "全选本栏") {
                        viewModel.toggleAllProfilePosts(in: visiblePosts)
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(visiblePosts.isEmpty)
                }

                if visiblePosts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: profileContentFilter.iconName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.tertiary)

                        Text(profileContentFilter.emptyTitle)
                            .font(.subheadline.weight(.semibold))

                        Text(profileContentFilter.emptyDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(visiblePosts) { post in
                            ProfilePostTile(
                                post: post,
                                isSelected: viewModel.selectedProfilePostIDs.contains(post.id)
                            ) {
                                viewModel.toggleProfilePost(post)
                            }
                        }
                    }
                }

                Button {
                    viewModel.saveSelectedProfilePosts()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.badge.plus")
                        Text("加入队列（\(viewModel.selectedProfilePostIDs.count)）")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.accent)
                .disabled(!viewModel.canSaveSelectedProfilePosts)
            }
            .padding(20)
            .surfaceCard(radius: 26)
            .animation(.snappy, value: profileContentFilter)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func profilePosts(for filter: ProfileContentFilter) -> [InstagramProfilePost] {
        switch filter {
        case .post:
            viewModel.profileRegularPosts
        case .reel:
            viewModel.profileReels
        case .story:
            viewModel.profileStories
        }
    }

    @ViewBuilder
    private var taskQueueSection: some View {
        if let currentJob = prioritizedJobs.first {
            let taskCount = prioritizedJobs.count

            SaveQueueProgressView(
                job: currentJob,
                queueCount: taskCount,
                cancelTitle: currentJob.batchID == nil ? "取消" : "取消全部",
                onRetry: { viewModel.retry(currentJob) },
                onForceSave: { viewModel.retry(currentJob, allowDuplicate: true) },
                onCancel: {
                    if currentJob.batchID == nil {
                        viewModel.cancel(currentJob)
                    } else {
                        viewModel.cancelBatch(containing: currentJob)
                    }
                },
                onRemove: { viewModel.remove(currentJob) }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var prioritizedJobs: [SaveJob] {
        viewModel.jobs.sorted { lhs, rhs in
            let leftPriority = jobPriority(lhs)
            let rightPriority = jobPriority(rhs)
            if leftPriority == rightPriority {
                return lhs.createdAt < rhs.createdAt
            }
            return leftPriority < rightPriority
        }
    }

    private func jobPriority(_ job: SaveJob) -> Int {
        if job.status.isRunning { return 0 }
        if job.status == .queued { return 1 }
        switch job.status {
        case .failed, .duplicate: return 2
        case .cancelled: return 3
        case .saved, .idle: return 4
        case .queued, .resolving, .downloading, .saving: return 0
        }
    }

}

private enum RecentContentFilter: String, CaseIterable, Identifiable {
    case all
    case post
    case reel
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .post: "帖子"
        case .reel: "Reels"
        case .story: "快拍"
        }
    }

    func matches(_ kind: InstagramContentKind) -> Bool {
        switch self {
        case .all: true
        case .post: kind == .post || kind == .direct || kind == .unknown
        case .reel: kind == .reel
        case .story: kind == .story
        }
    }
}

private struct RecentSaveGroup: Identifiable {
    let title: String
    let saves: [RecentSave]
    var id: String { title }
}

private struct MediaPreviewView: View {
    let resolution: MediaResolution
    let selectedAssetIDs: Set<UUID>
    let onToggle: (MediaAsset) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resolution.username.map { "@\($0)" } ?? resolution.sourceURL.host(percentEncoded: false) ?? "Instagram")
                            .font(.title3.weight(.bold))
                        Text("已识别 \(resolution.assets.count) 项，选择要保存的内容")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(resolution.assets) { asset in
                            PreviewAssetTile(
                                asset: asset,
                                isSelected: selectedAssetIDs.contains(asset.id)
                            ) {
                                onToggle(asset)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("保存预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onConfirm) {
                    Label("保存已选（\(selectedAssetIDs.count)）", systemImage: "arrow.down.to.line")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.accent)
                .disabled(selectedAssetIDs.isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }
}

private struct PreviewAssetTile: View {
    let asset: MediaAsset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                if asset.kind == .image {
                    AsyncImage(url: asset.sourceURL) { phase in
                        if case let .success(image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            ProgressView()
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [Brand.accent.opacity(0.72), Brand.violet.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(isSelected ? Brand.accent : .white)
                            .shadow(radius: 3)
                    }
                    Spacer()
                    HStack {
                        Label(asset.kind == .video ? "视频" : "图片", systemImage: asset.kind == .video ? "video.fill" : "photo.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: Capsule())
                        Spacer()
                    }
                }
                .padding(9)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsView: View {
    let sessionState: InstagramSessionState
    let onLogin: () -> Void
    let onLogout: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.dedicatedAlbumKey) private var usesDedicatedAlbum = false
    @AppStorage(AppPreferences.previewBeforeSavingKey) private var previewsBeforeSaving = true
    @AppStorage(AppPreferences.duplicateProtectionKey) private var protectsAgainstDuplicates = true
    @AppStorage(AppPreferences.cellularDownloadsKey) private var allowsCellularDownloads = true
    @AppStorage(AppPreferences.completionNotificationsKey) private var completionNotifications = true

    var body: some View {
        NavigationStack {
            Form {
                Section("保存流程") {
                    Toggle("保存链接前先预览", isOn: $previewsBeforeSaving)
                    Toggle("提醒重复保存", isOn: $protectsAgainstDuplicates)
                    Toggle("完成后通知", isOn: $completionNotifications)
                        .onChange(of: completionNotifications) { _, enabled in
                            if enabled {
                                Task { await NotificationService.requestAuthorizationIfNeeded() }
                            }
                        }
                }

                Section("保存位置") {
                    Toggle("整理到“IGSave”相册", isOn: $usesDedicatedAlbum)
                    Text(usesDedicatedAlbum ? "新保存的内容会同时加入 IGSave 系统相册。" : "内容直接添加到系统照片图库。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("网络") {
                    Toggle("允许蜂窝网络下载", isOn: $allowsCellularDownloads)
                    if !allowsCellularDownloads {
                        Text("使用移动数据时任务会失败并保留在列表中，可连接 Wi‑Fi 后重试。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Instagram 账号") {
                    LabeledContent("状态", value: sessionDescription)
                    if sessionState.isConnected {
                        Button("退出并清除登录数据", role: .destructive, action: onLogout)
                    } else {
                        Button("连接 Instagram", action: onLogin)
                    }
                }

                Section("系统权限") {
                    Button("打开 IGSave 系统设置", action: onOpenSettings)
                    Text("如果相册权限曾被拒绝，可在这里重新开启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("支持内容") {
                    Label("帖子与轮播帖子", systemImage: "rectangle.stack")
                    Label("Reels 短视频", systemImage: "play.rectangle")
                    Label("当前可访问的快拍", systemImage: "circle.dashed")
                    Text("内容只会保存到这台设备的系统照片图库。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var sessionDescription: String {
        switch sessionState {
        case let .connected(username): username.map { "已连接 @\($0)" } ?? "已连接"
        case .expired: "已过期"
        case .disconnected: "未连接"
        }
    }
}

private enum AppTab: Hashable {
    case save
    case recents
}

private enum SaveInputMode: Hashable {
    case link
    case profile
}

private enum ProfileContentFilter: Hashable {
    case post
    case reel
    case story

    var title: String {
        switch self {
        case .post:
            "最新帖子"
        case .reel:
            "最新 Reels"
        case .story:
            "当前快拍"
        }
    }

    var iconName: String {
        switch self {
        case .post:
            "rectangle.stack"
        case .reel:
            "play.rectangle"
        case .story:
            "circle.dashed"
        }
    }

    var emptyTitle: String {
        switch self {
        case .post:
            "暂无帖子"
        case .reel:
            "暂无 Reels"
        case .story:
            "暂无快拍"
        }
    }

    var emptyDescription: String {
        switch self {
        case .post:
            "这个账号最近没有可访问的帖子。"
        case .reel:
            "这个账号最近没有可访问的短视频。"
        case .story:
            "快拍可能已经过期，或当前账号无权查看。"
        }
    }
}

private enum Brand {
    static let accent = Color(red: 0.91, green: 0.18, blue: 0.36)
    static let violet = Color(red: 0.43, green: 0.28, blue: 0.72)
}

private struct AppBackdrop: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            Circle()
                .fill(Brand.accent.opacity(0.13))
                .frame(width: 280, height: 280)
                .blur(radius: 72)
                .offset(x: -150, y: -280)

            Circle()
                .fill(Brand.violet.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 82)
                .offset(x: 170, y: 170)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct ProfilePostTile: View {
    let post: InstagramProfilePost
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { proxy in
                ZStack {
                    placeholder

                    if let thumbnailURL = post.thumbnailURL {
                        AsyncImage(url: thumbnailURL) { phase in
                            if case let .success(image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    }

                    VStack {
                        HStack(alignment: .top) {
                            Label(post.contentKind.title, systemImage: post.contentKind.iconName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.46), in: Capsule())

                            Spacer()

                            Image(systemName: isSelected ? "checkmark" : "circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.95))
                                .frame(width: 28, height: 28)
                                .background(isSelected ? Brand.accent : .black.opacity(0.34), in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.88), lineWidth: 1.5)
                                }
                        }

                        Spacer()

                        if isSelected {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                Text("已选择")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Brand.accent.opacity(0.92), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 0.8)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(post.contentKind.title)，\(isSelected ? "已选择" : "未选择")")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Brand.accent.opacity(0.68), Brand.violet.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: post.contentKind.iconName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct RecentSaveRow: View {
    let save: RecentSave
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onSaveAgain: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            RecentPreview(filename: save.previewFilename, contentKind: save.contentKind)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(save.username)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(relativeTime)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 7) {
                    Label(save.contentKind.title, systemImage: save.contentKind.iconName)

                    Text("·")

                    Text("\(save.itemCount) 个文件")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            }

            Menu {
                Button("打开原链接", systemImage: "safari", action: onOpen)
                Button("复制链接", systemImage: "doc.on.doc", action: onCopy)
                Button("再次保存", systemImage: "arrow.clockwise", action: onSaveAgain)
                Divider()
                Button("删除记录", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 44)
            }
        }
        .padding(13)
        .surfaceCard(radius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var relativeTime: String {
        let calendar = Calendar.current
        if calendar.isDateInYesterday(save.savedAt) {
            return "昨天"
        }
        if !calendar.isDateInToday(save.savedAt) {
            let components = calendar.dateComponents([.month, .day], from: save.savedAt)
            return "\(components.month ?? 0)月\(components.day ?? 0)日"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: save.savedAt, relativeTo: Date())
    }
}

private struct RecentSaveDetailView: View {
    let save: RecentSave
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onSaveAgain: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 20) {
                        RecentDetailPreview(
                            filename: save.previewFilename,
                            contentKind: save.contentKind
                        )

                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(save.username)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(1)
                                Text("\(save.contentKind.title) · \(save.itemCount) 个文件")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Text(detailDate)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                detailAction(
                                    title: "再次保存",
                                    systemImage: "arrow.clockwise",
                                    isPrimary: true,
                                    action: onSaveAgain
                                )
                                detailAction(
                                    title: "Instagram",
                                    systemImage: "arrow.up.right",
                                    action: onOpen
                                )
                                detailAction(
                                    title: "复制链接",
                                    systemImage: "doc.on.doc",
                                    action: onCopy
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("保存详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("删除记录", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多操作")
                }
            }
        }
    }

    @ViewBuilder
    private func detailAction(
        title: String,
        systemImage: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
        }

        if isPrimary {
            button
                .buttonStyle(.glassProminent)
                .tint(Brand.accent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var detailDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: save.savedAt)
    }
}

private struct RecentDetailPreview: View {
    let filename: String?
    let contentKind: InstagramContentKind

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.94))

            if let url = RecentSaveStore.previewURL(for: filename) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure, .empty:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }

            if filename != nil {
                Text(contentKind.previewLabel)
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Brand.accent.opacity(0.9), Brand.violet.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(contentKind.previewLabel)
                .font(.title3.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SaveQueueProgressView: View {
    let job: SaveJob
    let queueCount: Int
    let cancelTitle: String
    let onRetry: () -> Void
    let onForceSave: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(job.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(job.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(job.status.tint)
                    .lineLimit(1)
            }

            ProgressView(value: job.status.progressFraction)
                .progressViewStyle(.linear)
                .tint(job.status.tint)
                .animation(.smooth, value: job.status.progressFraction)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if queueCount > 1 {
                        Text("队列中还有 \(queueCount - 1) 项")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                actionButtons
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var actionButtons: some View {
        GlassEffectContainer(spacing: 7) {
            HStack(spacing: 7) {
                switch job.status {
                case .queued, .idle, .resolving, .downloading, .saving:
                    Button(cancelTitle, role: .destructive, action: onCancel)
                        .buttonStyle(.glass)
                case .failed, .cancelled:
                    Button("重试", action: onRetry)
                        .buttonStyle(.glassProminent)
                        .tint(Brand.accent)
                    Button("移除", action: onRemove)
                        .buttonStyle(.glass)
                case .duplicate:
                    Button("保存", action: onForceSave)
                        .buttonStyle(.glassProminent)
                        .tint(Brand.accent)
                    Button("移除", action: onRemove)
                        .buttonStyle(.glass)
                case .saved:
                    EmptyView()
                }
            }
        }
        .font(.caption.weight(.semibold))
        .controlSize(.small)
    }
}

private struct RecentPreview: View {
    let filename: String?
    let contentKind: InstagramContentKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Brand.accent.opacity(0.92), Brand.violet.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let url = RecentSaveStore.previewURL(for: filename) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 0.8)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: contentKind == .reel || contentKind == .story ? "play.fill" : "photo")
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(.white)
    }
}

private struct SurfaceCardModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 6)
    }
}

private extension View {
    func surfaceCard(radius: CGFloat) -> some View {
        modifier(SurfaceCardModifier(radius: radius))
    }

    @ViewBuilder
    func recentSearchable(enabled: Bool, text: Binding<String>) -> some View {
        if enabled {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "搜索账号"
            )
        } else {
            self
        }
    }
}

private extension SaveStatus {
    var tint: Color {
        switch self {
        case .saved:
            .green
        case .duplicate:
            .orange
        case .failed:
            .red
        case .cancelled:
            .secondary
        case .idle, .queued:
            .secondary
        case .resolving, .downloading, .saving:
            Brand.accent
        }
    }

    var progressFraction: Double {
        switch self {
        case .idle, .queued:
            0.03
        case .resolving:
            0.1
        case let .downloading(current, total):
            0.1 + (Double(max(current - 1, 0)) / Double(max(total, 1))) * 0.8
        case let .saving(current, total):
            0.1 + ((Double(current) - 0.5) / Double(max(total, 1))) * 0.8
        case .saved, .duplicate, .failed:
            1
        case .cancelled:
            0
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "等待开始"
        case .queued:
            "已加入队列"
        case .resolving:
            "正在识别链接中的媒体"
        case let .downloading(current, total):
            "正在下载第 \(current) 项，共 \(total) 项"
        case let .saving(current, total):
            "正在写入相册，第 \(current) 项，共 \(total) 项"
        case let .saved(count):
            "\(count) 个文件已写入系统相册"
        case let .duplicate(previousSavedAt):
            "上次保存于 \(previousSavedAt.formatted(date: .abbreviated, time: .shortened))"
        case let .failed(message):
            message
        case .cancelled:
            "可以重新加入队列"
        }
    }
}

private extension SaveJob {
    var displayTitle: String {
        let kindTitle = contentKind?.title ?? inferredContentKind.title
        if let username, !username.isEmpty {
            return "@\(username) · \(kindTitle)"
        }
        if let identity = instagramIdentity {
            return "\(identity) · \(kindTitle)"
        }
        return kindTitle
    }

    private var instagramIdentity: String? {
        let components = sourceURL?.pathComponents.filter { $0 != "/" } ?? []

        if let storyIndex = components.firstIndex(of: "stories"),
           components.indices.contains(storyIndex + 1) {
            return "@\(components[storyIndex + 1])"
        }

        for route in ["p", "reel", "tv"] {
            if let routeIndex = components.firstIndex(of: route),
               components.indices.contains(routeIndex + 1) {
                return components[routeIndex + 1]
            }
        }

        return nil
    }

    private var inferredContentKind: InstagramContentKind {
        let components = sourceURL?.pathComponents.filter { $0 != "/" } ?? []
        if components.contains("stories") { return .story }
        if components.contains("reel") || components.contains("tv") { return .reel }
        if components.contains("p") { return .post }
        return .unknown
    }

    private var sourceURL: URL? {
        if let url = URL(string: input), url.scheme != nil {
            return url
        }

        return input
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { URL(string: String($0)) }
            .first { $0.scheme != nil }
    }
}

private extension InstagramContentKind {
    var title: String {
        switch self {
        case .direct:
            "媒体直链"
        case .post:
            "帖子"
        case .reel:
            "Reel"
        case .story:
            "快拍"
        case .unknown:
            "媒体"
        }
    }

    var iconName: String {
        switch self {
        case .direct:
            "link"
        case .post:
            "rectangle.stack"
        case .reel:
            "play.rectangle"
        case .story:
            "circle.dashed"
        case .unknown:
            "photo"
        }
    }

    var previewLabel: String {
        switch self {
        case .direct:
            "MEDIA"
        case .post:
            "POST"
        case .reel:
            "REEL"
        case .story:
            "STORY"
        case .unknown:
            "IG"
        }
    }
}

#Preview {
    ContentView()
}
