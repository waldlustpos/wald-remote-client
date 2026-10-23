import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  // iOS 27 SDK 부터 scene 생명주기가 필수라 창은 SceneDelegate 가 만든다. 시작 때 window 가 없어
  // register(with: self) 가 플러그인을 못 찾으므로 엔진을 여기서 만들어 등록하고 SceneDelegate 가 쓴다.
  lazy var flutterEngine = FlutterEngine(name: "waldlust")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    dummyMethodToEnforceBundling();
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
    
  public func dummyMethodToEnforceBundling() {
      dummy_method_to_enforce_bundling();
    session_get_rgba(nil, 0);
  }
}
