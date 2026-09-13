import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": true, "app": "REYDL"]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
