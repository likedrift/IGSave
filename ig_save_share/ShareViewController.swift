import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let appGroupIdentifier = "group.com.haru.ig-save"
    private static let pendingLinksKey = "pending-import-links-v1"

    private let panelView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let iconView = UIImageView()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()

        Task { @MainActor in
            await importSharedLink()
        }
    }

    private func configureView() {
        preferredContentSize = CGSize(width: 0, height: 250)
        view.backgroundColor = .systemGroupedBackground

        panelView.layer.cornerRadius = 28
        panelView.clipsToBounds = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelView)

        iconView.image = UIImage(systemName: "square.and.arrow.down.fill")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        iconView.tintColor = UIColor(red: 0.91, green: 0.18, blue: 0.36, alpha: 1)
        iconView.contentMode = .scaleAspectFit

        statusLabel.text = "正在加入 IGSave…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        activityIndicator.startAnimating()

        closeButton.setTitle("关闭", for: .normal)
        closeButton.configuration = .tinted()
        closeButton.configuration?.cornerStyle = .capsule
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [iconView, statusLabel, activityIndicator, closeButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            panelView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            panelView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            panelView.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),
            stack.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: panelView.contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 52),
            iconView.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func importSharedLink() async {
        guard let link = await firstSharedLink() else {
            showFailure("没有在分享内容中找到链接。")
            return
        }

        guard storePendingLink(link) else {
            showFailure("暂时无法写入共享队列，请稍后再试。")
            return
        }

        activityIndicator.stopAnimating()
        iconView.image = UIImage(systemName: "checkmark.circle.fill")
        iconView.tintColor = .systemGreen
        statusLabel.text = "已加入保存队列\n打开 IGSave 后自动处理"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIView.animate(withDuration: 0.25) {
            self.panelView.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        } completion: { _ in
            UIView.animate(withDuration: 0.2) {
                self.panelView.transform = .identity
            }
        }
        try? await Task.sleep(for: .milliseconds(1_250))
        extensionContext?.completeRequest(returningItems: nil)
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

    private func storePendingLink(_ link: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            return false
        }

        var links = defaults.stringArray(forKey: Self.pendingLinksKey) ?? []
        links.append(link)
        defaults.set(Array(links.suffix(20)), forKey: Self.pendingLinksKey)
        return true
    }

    @MainActor
    private func showFailure(_ message: String) {
        activityIndicator.stopAnimating()
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        iconView.tintColor = .systemRed
        statusLabel.text = message
        closeButton.isHidden = false
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    @objc private func close() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
