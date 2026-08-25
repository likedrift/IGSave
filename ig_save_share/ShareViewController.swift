import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()

        Task { @MainActor in
            await importSharedLink()
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "正在读取 Instagram 链接…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        closeButton.setTitle("关闭", for: .normal)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [statusLabel, closeButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func importSharedLink() async {
        guard let link = await firstSharedLink() else {
            showFailure("没有在分享内容中找到链接。")
            return
        }

        var components = URLComponents()
        components.scheme = "igsave"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "url", value: link)]

        guard let deepLink = components.url else {
            showFailure("这个链接暂时无法导入。")
            return
        }

        let success = await extensionContext?.open(deepLink) ?? false
        if success {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            showFailure("无法打开 IG Save，请先从主屏幕启动一次 App。")
        }
    }

    private func firstSharedLink() async -> String? {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
               let link = linkString(from: item) {
                return link
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
               let link = linkString(from: item) {
                return link
            }
        }

        return nil
    }

    private func linkString(from item: NSSecureCoding) -> String? {
        if let url = item as? URL {
            return url.absoluteString
        }

        guard let text = item as? String else {
            return nil
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, range: range)?.url?.absoluteString
    }

    @MainActor
    private func showFailure(_ message: String) {
        statusLabel.text = message
        closeButton.isHidden = false
    }

    @objc private func close() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
