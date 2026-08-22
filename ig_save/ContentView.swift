//
//  ContentView.swift
//  ig_save
//
//  Created by yank on 2026/5/4.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = DownloadViewModel()
    @State private var selectedTab: AppTab = .save
    @State private var inputMode: SaveInputMode = .link
    @State private var profileContentFilter: ProfileContentFilter = .post
    @FocusState private var isInputFocused: Bool

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
        .task {
            await viewModel.refreshInstagramSessionStatus()
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
    }

    private var saveNavigation: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 24) {
                        saveHero
                        linkComposer
                        profilePostsSection
                        statusPanel
                        supportCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("IG Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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

                if viewModel.recentSaves.isEmpty {
                    ContentUnavailableView(
                        "还没有保存记录",
                        systemImage: "photo.stack",
                        description: Text("保存成功的帖子、Reel 和快拍会显示在这里。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(viewModel.recentSaves) { save in
                                RecentSaveRow(save: save)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("最近保存")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(viewModel.recentSaves.count) / 5")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var saveHero: some View {
        HStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: 27, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Brand.accent)
                .frame(width: 58, height: 58)
                .background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("保存喜欢的内容")
                    .font(.title2.weight(.bold))

                Text("粘贴链接，一步存入系统相册")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Brand.accent.opacity(0.13),
                    Brand.violet.opacity(0.07),
                    Color(uiColor: .secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.38), lineWidth: 0.8)
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

                    Text(viewModel.hasInstagramSession ? "可以读取当前账号有权访问的内容" : "账号获取和快拍需要登录")
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
                            if viewModel.isWorking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.down.to.line")
                            }

                            Text(viewModel.isWorking ? "正在保存" : "保存到相册")
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
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

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

                        Text(profileContentFilter.emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                        if viewModel.isWorking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.down.to.line")
                        }

                        Text(viewModel.isWorking ? "正在保存" : "保存已选（\(viewModel.selectedProfilePostIDs.count)）")
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
    private var statusPanel: some View {
        if let job = viewModel.jobs.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: job.status.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(job.status.tint)
                        .frame(width: 34, height: 34)
                        .background(job.status.tint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.status.title)
                            .font(.subheadline.weight(.semibold))

                        Text(job.status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if job.status.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(job.input)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(16)
            .background(job.status.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("支持内容")
                .font(.headline)

            HStack(spacing: 8) {
                SupportBadge(title: "帖子", icon: "rectangle.stack")
                SupportBadge(title: "Reel", icon: "play.rectangle")
                SupportBadge(title: "快拍", icon: "circle.dashed")
            }

            Label("内容只保存在这台设备的系统相册中", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .surfaceCard(radius: 24)
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

    var emptyMessage: String {
        switch self {
        case .post:
            "这个账号暂时没有可访问的帖子"
        case .reel:
            "这个账号暂时没有可访问的 Reels"
        case .story:
            "这个账号目前没有可访问的快拍"
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

private struct SupportBadge: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.primary.opacity(0.045), in: Capsule())
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

    var body: some View {
        HStack(spacing: 15) {
            RecentPreview(filename: save.previewFilename, contentKind: save.contentKind)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(save.username)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(save.savedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 7) {
                    Label(save.contentKind.title, systemImage: save.contentKind.iconName)

                    Text("·")

                    Text("\(save.itemCount) 个文件")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Text(save.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(13)
        .surfaceCard(radius: 22)
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
}

private extension SaveStatus {
    var iconName: String {
        switch self {
        case .idle:
            "clock"
        case .resolving:
            "sparkle.magnifyingglass"
        case .downloading:
            "arrow.down.circle"
        case .saving:
            "photo.badge.plus"
        case .saved:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .saved:
            .green
        case .failed:
            .red
        case .idle:
            .secondary
        case .resolving, .downloading, .saving:
            Brand.accent
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "等待开始"
        case .resolving:
            "正在识别链接中的媒体"
        case let .downloading(current, total):
            "正在下载第 \(current) 项，共 \(total) 项"
        case let .saving(current, total):
            "正在写入相册，第 \(current) 项，共 \(total) 项"
        case let .saved(count):
            "\(count) 个文件已写入系统相册"
        case let .failed(message):
            message
        }
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
}

private extension RecentSave {
    var sourceSummary: String {
        guard let url = URL(string: sourceURL) else {
            return sourceURL
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if path.isEmpty {
            return url.host(percentEncoded: false) ?? sourceURL
        }

        return path
    }
}

#Preview {
    ContentView()
}
