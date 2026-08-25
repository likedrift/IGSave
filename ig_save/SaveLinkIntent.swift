import AppIntents

struct SaveInstagramLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "保存 Instagram 链接"
    static let description = IntentDescription("把帖子、Reel 或快拍链接加入 IG Save 保存队列。")
    static let openAppWhenRun = true

    @Parameter(title: "Instagram 链接")
    var link: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingImportStore.add(link)
        return .result(dialog: "链接已加入 IG Save。")
    }
}

struct IGSaveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveInstagramLinkIntent(),
            phrases: [
                "用 \(.applicationName) 保存 Instagram 链接",
                "添加链接到 \(.applicationName)"
            ],
            shortTitle: "保存 Instagram",
            systemImageName: "square.and.arrow.down"
        )
    }
}
