import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    var launched = false;
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
      dummy_method_to_enforce_bundling()
    // https://github.com/leanflutter/window_manager/issues/214
    return false
  }
    
    override func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if (launched) {
            handle_applicationShouldOpenUntitledFile();
        }
        return true
    }
    
    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        launched = true;
        NSApplication.shared.activate(ignoringOtherApps: true);
    }

    // Waldlust(DSK-07, 부록 A-41): 창을 닫아 메뉴 막대 아이콘만 남은 상태에서 Finder·Spotlight 로 다시 실행하면
    // 메인 창을 띄운다.
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && WaldStatusItem.shared.requestOpen() {
            return false
        }
        return true
    }

    // Waldlust(DSK-07, 부록 A-41): 메뉴 막대 '종료'는 확인 없이 바로 끝낸다.
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if WaldStatusItem.shared.quitting {
            return .terminateNow
        }
        return super.applicationShouldTerminate(sender)
    }

    // Waldlust(DSK-07, 부록 A-41): 메뉴 막대 '종료'·Cmd+Q 로 끝낼 때 앱이 띄운 연결 관리 창도 함께 끝낸다.
    override func applicationWillTerminate(_ notification: Notification) {
        WaldStatusItem.terminateChildInstances()
    }
}
