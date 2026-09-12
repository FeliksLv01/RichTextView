import RichTextView
import UIKit

@MainActor
final class ExampleRemoteImageLoader: RichImageLoader {
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadImage(
        for source: RichImageSource,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> RichImageLoadTask? {
        let identifier = source.identifier
        if let image = cache.object(forKey: identifier as NSString) {
            completion(image)
            return nil
        }
        guard source.loadsRemotely, let url = URL(string: source.identifier) else {
            completion(source.image)
            return nil
        }

        let task = session.dataTask(with: url) { [weak self] data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let imageData = (200..<300).contains(statusCode) ? data : nil
            Task { @MainActor [weak self] in
                let image = imageData.flatMap(UIImage.init(data:))
                if let image {
                    self?.cache.setObject(image, forKey: identifier as NSString)
                }
                completion(image)
            }
        }
        task.resume()
        return RichImageLoadTask {
            task.cancel()
        }
    }
}
