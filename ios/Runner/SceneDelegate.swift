import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      for context in connectionOptions.urlContexts {
        _ = appDelegate.acceptGenerationActivationURL(context.url)
      }
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      super.scene(scene, openURLContexts: URLContexts)
      return
    }
    let unhandled = URLContexts.filter {
      !appDelegate.acceptGenerationActivationURL($0.url)
    }
    if !unhandled.isEmpty {
      super.scene(scene, openURLContexts: Set(unhandled))
    }
  }
}
