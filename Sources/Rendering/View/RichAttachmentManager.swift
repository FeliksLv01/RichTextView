import UIKit

@MainActor
final class RichAttachmentManager {
    private struct MountedAttachment {
        let reuseIdentifier: String
        let provider: any RichAttachmentViewProvider
        let view: UIView
    }

    private weak var hostView: UIView?
    private let poolCapacityPerIdentifier: Int
    private var mounted: [String: MountedAttachment] = [:]
    private var reusePools: [String: [UIView]] = [:]

    init(hostView: UIView, poolCapacityPerIdentifier: Int = 8) {
        self.hostView = hostView
        self.poolCapacityPerIdentifier = max(0, poolCapacityPerIdentifier)
    }

    func apply(_ runBoxes: [RichAttachmentRunBox]) {
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
            let view = dequeue(reuseIdentifier: element.reuseIdentifier) ?? element.provider.makeView()
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

    func prepareForReuse() {
        let ids = Array(mounted.keys)
        ids.forEach(unmount)
    }

    private func unmount(_ elementID: String) {
        guard let attachment = mounted.removeValue(forKey: elementID) else { return }
        attachment.provider.prepareForReuse(attachment.view)
        attachment.view.removeFromSuperview()
        guard poolCapacityPerIdentifier > 0 else { return }
        var pool = reusePools[attachment.reuseIdentifier, default: []]
        if pool.count < poolCapacityPerIdentifier {
            pool.append(attachment.view)
            reusePools[attachment.reuseIdentifier] = pool
        }
    }

    private func dequeue(reuseIdentifier: String) -> UIView? {
        guard var pool = reusePools[reuseIdentifier], let view = pool.popLast() else { return nil }
        reusePools[reuseIdentifier] = pool
        return view
    }
}
