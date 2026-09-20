import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let navigation = UINavigationController(rootViewController: ExampleListViewController())
        window.rootViewController = navigation
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--example=") }),
           let example = ExampleCase(rawValue: String(argument.dropFirst("--example=".count))) {
            navigation.pushViewController(ExampleDetailViewController(example: example), animated: false)
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}
