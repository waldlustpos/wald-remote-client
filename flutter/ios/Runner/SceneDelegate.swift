import UIKit
import Flutter

// iOS 27 SDK 의 scene 생명주기 필수 대응(DSK-12). AppDelegate 가 띄운 엔진으로 창을 만든다.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
          let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = FlutterViewController(
      engine: appDelegate.flutterEngine, nibName: nil, bundle: nil)
    window.makeKeyAndVisible()
    self.window = window
    // 옛 플러그인은 앱 델리게이트의 window 로 화면을 띄운다
    appDelegate.window = window
    open(connectionOptions.urlContexts)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    open(URLContexts)
  }

  // waldlust:// 링크를 앱 델리게이트로 넘겨 uni_links 가 받게 한다
  private func open(_ contexts: Set<UIOpenURLContext>) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    for context in contexts {
      _ = appDelegate.application(UIApplication.shared, open: context.url, options: [:])
    }
  }
}
