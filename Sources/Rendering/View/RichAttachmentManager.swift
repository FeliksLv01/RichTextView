import UIKit

@MainActor
final class RichAttachmentManager {
    private struct MountedAttachment {
        let reuseIdentifier: String
        let provider: any RichAttachmentViewProvider
        let view: UIView
    }

    private weak var hostView: UIView?
    private weak var ownerViewController: UIViewController?
    private var mounted: [String: MountedAttachment] = [:]

    init(hostView: UIView) {
        self.hostView = hostView
    }

    func apply(_ runBoxes: [RichAttachmentRunBox]) {
        updateOwnerViewController()
        let requiredIDs = Set(runBoxes.map(\.id))
        let removedIDs = mounted.keys.filter { !requiredIDs.contains($0) }
        removedIDs.forEach(unmount)

        for runBox in runBoxes {
            let element = runBox.element
            if let current = mounted[element.id],
               current.reuseIdentifier == element.reuseIdentifier {
                element.provider.updateView(current.view)
                current.view.frame = runBox.contentFrame.integral
                if current.view.superview !== hostView {
                    hostView?.addSubview(current.view)
                }
                mounted[element.id] = MountedAttachment(
                    reuseIdentifier: element.reuseIdentifier,
                    provider: element.provider,
                    view: current.view
                )
                continue
            }

            unmount(element.id)
            let view = reusePool?.dequeue(reuseIdentifier: element.reuseIdentifier) ?? element.provider.makeView()
            element.provider.updateView(view)
            view.frame = runBox.contentFrame.integral
            hostView?.addSubview(view)
            mounted[element.id] = MountedAttachment(
                reuseIdentifier: element.reuseIdentifier,
                provider: element.provider,
                view: view
            )
        }
    }

    func view(for id: String) -> UIView? { mounted[id]?.view }

    func prepareForReuse() {
        updateOwnerViewController()
        let ids = Array(mounted.keys)
        ids.forEach(unmount)
    }

    private func updateOwnerViewController() {
        var responder: UIResponder? = hostView
        while let current = responder {
            if let owner = current as? UIViewController {
                ownerViewController = owner
                return
            }
            responder = current.next
        }
        ownerViewController = nil
    }

    private var reusePool: RichAttachmentReusePool? {
        ownerViewController.map { RichAttachmentPoolRegistry.shared.pool(for: $0) }
    }

    private func unmount(_ elementID: String) {
        guard let attachment = mounted.removeValue(forKey: elementID) else { return }
        attachment.provider.prepareForReuse(attachment.view)
        attachment.view.removeFromSuperview()
        reusePool?.enqueue(attachment.view, for: attachment.reuseIdentifier)
    }
}

@MainActor
private final class RichAttachmentPoolRegistry {
    static let shared = RichAttachmentPoolRegistry()
    private typealias PagePools = NSMapTable<UIViewController, RichAttachmentReusePool>
    private var pools = PagePools.weakToStrongObjects()
    private static var lifetimeKey: UInt8 = 0

    private init() {
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pools.removeAllObjects() }
        }
    }

    func pool(for owner: UIViewController) -> RichAttachmentReusePool {
        if let pool = pools.object(forKey: owner) { return pool }
        let pool = RichAttachmentReusePool()
        pools.setObject(pool, forKey: owner)
        if objc_getAssociatedObject(owner, &Self.lifetimeKey) == nil {
            objc_setAssociatedObject(owner, &Self.lifetimeKey, PageLifetime(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return pool
    }

    // NSMapTable can retain a value after its weak key dies. Drop those entries
    // at controller teardown, even if no other host ever accesses the registry.
    private func discardReleasedPages() {
        let livePools = PagePools.weakToStrongObjects()
        for case let owner as UIViewController in pools.keyEnumerator() {
            livePools.setObject(pools.object(forKey: owner), forKey: owner)
        }
        pools = livePools
    }

    private final class PageLifetime {
        deinit {
            if Thread.isMainThread {
                MainActor.assumeIsolated { RichAttachmentPoolRegistry.shared.discardReleasedPages() }
            } else {
                DispatchQueue.main.async { RichAttachmentPoolRegistry.shared.discardReleasedPages() }
            }
        }
    }
}

@MainActor
private final class RichAttachmentReusePool {
    private var pools: [String: [UIView]] = [:]
    private var count = 0

    func enqueue(_ view: UIView, for identifier: String) {
        guard count < 12, (pools[identifier]?.count ?? 0) < 4 else { return }
        pools[identifier, default: []].append(view)
        count += 1
    }

    func dequeue(reuseIdentifier: String) -> UIView? {
        guard let view = pools[reuseIdentifier]?.popLast() else { return nil }
        if pools[reuseIdentifier]?.isEmpty == true { pools.removeValue(forKey: reuseIdentifier) }
        count -= 1
        return view
    }
}
