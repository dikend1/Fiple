import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The "Share → Fiple" entry point. Hosts the SwiftUI card that finds the Mac,
/// authenticates with the pairing token from the shared keychain group, and
/// beams the shared item — a file into ~/Downloads, text/URL onto the clipboard.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        let host = UIHostingController(rootView: ShareView(
            attachments: attachments,
            onFinish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
