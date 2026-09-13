import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let button = UIButton(type: .system)
    private var capturedText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Share to NEXUS"
        label.font = .preferredFont(forTextStyle: .title2)
        label.textAlignment = .center
        label.numberOfLines = 0
        button.setTitle("Send to NEXUS", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: #selector(sendToNexus), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        readSharedItems()
    }

    private func readSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        let providers = items.flatMap { $0.attachments ?? [] }
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                let text = (item as? URL)?.absoluteString ?? (item as? String) ?? ""
                DispatchQueue.main.async { self?.capturedText = text; self?.label.text = text.isEmpty ? "Share to NEXUS" : "Ready to capture\n\(text)" }
            }
            return
        }
        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
                let text = (item as? String) ?? ""
                DispatchQueue.main.async { self?.capturedText = text; self?.label.text = text.isEmpty ? "Share to NEXUS" : "Ready to capture\n\(String(text.prefix(180)))" }
            }
        }
    }

    @objc private func sendToNexus() {
        if !capturedText.isEmpty { UIPasteboard.general.string = capturedText }
        guard let url = URL(string: "nexus://capture") else { extensionContext?.completeRequest(returningItems: nil); return }
        extensionContext?.open(url) { [weak self] _ in self?.extensionContext?.completeRequest(returningItems: nil) }
    }
}
