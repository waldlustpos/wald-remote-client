import Cocoa
import AVFoundation
import FlutterMacOS
import desktop_multi_window
// import bitsdojo_window_macos

import desktop_drop
import device_info_plus
import flutter_custom_cursor
import package_info_plus
import path_provider_foundation
import screen_retriever
import sqflite
// import tray_manager
import uni_links_desktop
import url_launcher_macos
import wakelock_plus
import window_manager
import window_size
import texture_rgba_renderer

// Global state for relative mouse mode
// All properties and methods must be accessed on the main thread since they
// interact with NSEvent monitors, CoreGraphics APIs, and Flutter channels.
// Note: We avoid @MainActor to maintain macOS 10.14 compatibility.
class RelativeMouseState {
    static let shared = RelativeMouseState()

    var enabled = false
    var eventMonitor: Any?
    var deltaChannel: FlutterMethodChannel?
    var accumulatedDeltaX: CGFloat = 0
    var accumulatedDeltaY: CGFloat = 0

    private init() {}
}

// Waldlust(DSK-07): 상단 탭 막대(앱바)를 40pt 로 높였으므로(Dart kDesktopRemoteTabBarHeight 와 같은 값)
// 신호등 버튼을 그 막대의 세로 가운데로 옮긴다. 제목 표시줄은 숨긴 스타일(투명·fullSizeContentView)이라
// 기본으로는 28pt 막대 기준에 놓인다. 제목 표시줄 영역(창 끌기 영역)도 같은 높이로 늘린다.
// AppKit 이 크기 변경·전체화면 해제·키 창 전환 때 다시 배치하므로 그때마다 다시 맞춘다.
enum WaldTitleBar {
    static let height: CGFloat = 40

    static func attach(_ window: NSWindow) {
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didChangeScreenNotification,
        ]
        for name in names {
            tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                if let window = window { layout(window) }
            })
        }
        var closeToken: NSObjectProtocol?
        closeToken = center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            tokens.forEach { center.removeObserver($0) }
            if let closeToken = closeToken { center.removeObserver(closeToken) }
        }
        DispatchQueue.main.async { [weak window] in
            if let window = window { layout(window) }
        }
    }

    static func layout(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebarView = close.superview,
              let container = titlebarView.superview else { return }
        let parentHeight = container.superview?.bounds.height ?? window.frame.height
        let target = NSRect(x: container.frame.origin.x, y: parentHeight - height,
                            width: container.frame.width, height: height)
        if container.frame != target {
            container.frame = target
        }
        if titlebarView.frame != container.bounds {
            titlebarView.frame = container.bounds
        }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            let y = ((height - button.frame.height) / 2).rounded()
            if button.frame.origin.y != y {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
            }
        }
    }
}

// Waldlust(DSK-07, 부록 A-41): 메뉴 막대(상단 바) 아이콘. 원격 서비스가 이 프로세스 안에서 도는 동안
// Dart(flutter/lib/common/wald_mac_status_item.dart)가 켜고 끈다. '열기'는 Dart 에 알려 메인 창을 띄우고,
// '종료'는 앱을 끝낸다(Cmd+Q 와 같은 경로 — AppDelegate 가 앱이 띄운 연결 관리 창도 함께 끝낸다).
final class WaldStatusItem: NSObject {
    static let shared = WaldStatusItem()

    private var channel: FlutterMethodChannel?
    private var item: NSStatusItem?
    /// '종료'를 눌렀다. AppDelegate.applicationShouldTerminate 가 Flutter 종료 처리기(Dart 응답을 기다리다
    /// 취소될 수 있다 — flutter/lib/common.dart onActiveWindowChanged 주석)를 거치지 않고 바로 끝낸다.
    private(set) var quitting = false

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "co.kr.waldlust/status_item", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update", let args = call.arguments as? [String: Any] else {
                result(FlutterMethodNotImplemented)
                return
            }
            self?.update(args)
            result(nil)
        }
        self.channel = channel
    }

    private func update(_ args: [String: Any]) {
        guard args["visible"] as? Bool == true else {
            if let item = item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
            return
        }
        let item = self.item ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        if let data = (args["icon"] as? FlutterStandardTypedData)?.data,
           let image = NSImage(data: data), image.size.height > 0 {
            // src/tray.rs(tray-icon 크레이트)와 같이 높이 18pt 에 맞추고 템플릿으로 그린다(밝은·어두운 막대 모두).
            let height: CGFloat = 18
            image.size = NSSize(width: image.size.width * height / image.size.height, height: height)
            image.isTemplate = true
            item.button?.image = image
        }
        item.button?.toolTip = args["tooltip"] as? String
        let menu = NSMenu()
        let open = NSMenuItem(title: args["open"] as? String ?? "Open", action: #selector(onOpen), keyEquivalent: "")
        open.target = self
        let quit = NSMenuItem(title: args["quit"] as? String ?? "Quit", action: #selector(onQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(open)
        menu.addItem(quit)
        item.menu = menu
    }

    /// 아이콘이 떠 있으면(창을 닫아 백그라운드일 수 있으면) Dart 에 메인 창을 띄우라고 알리고 true 를 돌려준다.
    func requestOpen() -> Bool {
        guard item != nil, let channel = channel else { return false }
        channel.invokeMethod("open", arguments: nil)
        return true
    }

    @objc private func onOpen() {
        channel?.invokeMethod("open", arguments: nil)
    }

    @objc private func onQuit() {
        quitting = true
        NSApp.terminate(nil)
    }

    /// 이 프로세스가 띄운 같은 실행 파일의 자식(앱 안 서버가 띄운 연결 관리 창 `--cm`)을 끝낸다.
    /// 메인 앱만 끝나면 연결 관리 창이 '연결 끊김' 탭으로 남는다. 자식만 보므로 연결 관리 창이 끝날 때
    /// 메인 앱을 건드리지 않고, launchd 가 띄운 `--server` 도 건드리지 않는다.
    static func terminateChildInstances() {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return }
        var pids = [pid_t](repeating: 0, count: 64)
        guard proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size)) > 0 else { return }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            if URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path == exe {
                kill(pid, SIGTERM)
            }
        }
    }
}

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        rustdesk_core_main();
        let flutterViewController = FlutterViewController.init()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        // register self method handler
        let registrar = flutterViewController.registrar(forPlugin: "RustDeskPlugin")
        setMethodHandler(registrar: registrar)
        // Waldlust(DSK-07, 부록 A-41): 메뉴 막대 아이콘 채널은 메인 창 엔진에만 붙인다.
        WaldStatusItem.shared.attach(messenger: registrar.messenger)

        RegisterGeneratedPlugins(registry: flutterViewController)

        FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
            // Register the plugin which you want access from other isolate.
            // DesktopLifecyclePlugin.register(with: controller.registrar(forPlugin: "DesktopLifecyclePlugin"))
            // Note: copy below from above RegisterGeneratedPlugins
            self.setMethodHandler(registrar: controller.registrar(forPlugin: "RustDeskPlugin"))
            // Waldlust(DSK-07): desktop_drop 0.4.4 macOS 는 드롭 영역을 늘 메인 창에 붙여 하위 창(파일 전송)에
            // 드롭이 들어오지 않는다. 이 창 몫으로 메인 창에 새로 붙은 영역을 이 창으로 옮긴다(부록 A-37).
            let mainSubviews = flutterViewController.view.subviews
            DesktopDropPlugin.register(with: controller.registrar(forPlugin: "DesktopDropPlugin"))
            for view in flutterViewController.view.subviews where !mainSubviews.contains(view) {
                view.removeFromSuperview()
                view.frame = controller.view.bounds
                controller.view.addSubview(view)
            }
            DeviceInfoPlusMacosPlugin.register(with: controller.registrar(forPlugin: "DeviceInfoPlusMacosPlugin"))
            FlutterCustomCursorPlugin.register(with: controller.registrar(forPlugin: "FlutterCustomCursorPlugin"))
            FPPPackageInfoPlusPlugin.register(with: controller.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
            PathProviderPlugin.register(with: controller.registrar(forPlugin: "PathProviderPlugin"))
            SqflitePlugin.register(with: controller.registrar(forPlugin: "SqflitePlugin"))
            // TrayManagerPlugin.register(with: controller.registrar(forPlugin: "TrayManagerPlugin"))
            UniLinksDesktopPlugin.register(with: controller.registrar(forPlugin: "UniLinksDesktopPlugin"))
            UrlLauncherPlugin.register(with: controller.registrar(forPlugin: "UrlLauncherPlugin"))
            WakelockPlusMacosPlugin.register(with: controller.registrar(forPlugin: "WakelockPlusMacosPlugin"))
            WindowSizePlugin.register(with: controller.registrar(forPlugin: "WindowSizePlugin"))
            TextureRgbaRendererPlugin.register(with: controller.registrar(forPlugin: "TextureRgbaRendererPlugin"))
            // Waldlust(DSK-07): 원격·파일 전송 등 하위 창도 신호등을 높인 탭 막대에 맞춘다.
            if let window = controller.view.window {
                WaldTitleBar.attach(window)
            }
        }

        super.awakeFromNib()
        // Waldlust(DSK-07): 메인 창 신호등을 높인 탭 막대에 맞춘다.
        WaldTitleBar.attach(self)
    }

    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
    }

    /// Override window theme.
    public func setWindowInterfaceMode(window: NSWindow, themeName: String) {
        window.appearance = NSAppearance(named: themeName == "light" ? .aqua : .darkAqua)
    }

    private func enableNativeRelativeMouseMode(channel: FlutterMethodChannel) -> Bool {
        assert(Thread.isMainThread, "enableNativeRelativeMouseMode must be called on the main thread")
        let state = RelativeMouseState.shared
        if state.enabled {
            // Already enabled: update the channel so this caller receives deltas.
            state.deltaChannel = channel
            return true
        }

        // Dissociate mouse from cursor position - this locks the cursor in place
        // Do this FIRST before setting any state
        let result = CGAssociateMouseAndMouseCursorPosition(0)
        if result != CGError.success {
            NSLog("[RustDesk] Failed to dissociate mouse from cursor position: %d", result.rawValue)
            return false
        }

        // Only set state after CG call succeeds
        state.deltaChannel = channel
        state.accumulatedDeltaX = 0
        state.accumulatedDeltaY = 0

        // Add local event monitor to capture mouse delta.
        // Note: Local event monitors are always called on the main thread,
        // so accessing main-thread-only state is safe here.
        state.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak state] event in
            guard let state = state else { return event }
            // Guard against race: mode may be disabled between weak capture and this check.
            guard state.enabled else { return event }
            let deltaX = event.deltaX
            let deltaY = event.deltaY

            if deltaX != 0 || deltaY != 0 {
                // Accumulate delta (main thread only - NSEvent local monitors always run on main thread)
                state.accumulatedDeltaX += deltaX
                state.accumulatedDeltaY += deltaY

                // Only send if we have integer movement
                let intX = Int(state.accumulatedDeltaX)
                let intY = Int(state.accumulatedDeltaY)

                if intX != 0 || intY != 0 {
                    state.accumulatedDeltaX -= CGFloat(intX)
                    state.accumulatedDeltaY -= CGFloat(intY)

                    // Send delta to Flutter (already on main thread)
                    state.deltaChannel?.invokeMethod("onMouseDelta", arguments: ["dx": intX, "dy": intY])
                }
            }

            return event
        }

        // Check if monitor was created successfully
        if state.eventMonitor == nil {
            NSLog("[RustDesk] Failed to create event monitor for relative mouse mode")
            // Re-associate mouse since we failed
            CGAssociateMouseAndMouseCursorPosition(1)
            state.deltaChannel = nil
            return false
        }

        // Set enabled LAST after everything succeeds
        state.enabled = true
        return true
    }

    private func disableNativeRelativeMouseMode() {
        assert(Thread.isMainThread, "disableNativeRelativeMouseMode must be called on the main thread")
        let state = RelativeMouseState.shared
        if !state.enabled { return }

        state.enabled = false

        // Remove event monitor
        if let monitor = state.eventMonitor {
            NSEvent.removeMonitor(monitor)
            state.eventMonitor = nil
        }

        state.deltaChannel = nil
        state.accumulatedDeltaX = 0
        state.accumulatedDeltaY = 0

        // Re-associate mouse with cursor position (non-blocking with async retry)
        let result = CGAssociateMouseAndMouseCursorPosition(1)
        if result != CGError.success {
            NSLog("[RustDesk] Failed to re-associate mouse with cursor position: %d, scheduling retry...", result.rawValue)
            // Non-blocking retry after 50ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let retryResult = CGAssociateMouseAndMouseCursorPosition(1)
                if retryResult != CGError.success {
                    NSLog("[RustDesk] Retry failed to re-associate mouse: %d. Cursor may remain locked.", retryResult.rawValue)
                }
            }
        }
    }

    public func setMethodHandler(registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.rustdesk.rustdesk/host", binaryMessenger: registrar.messenger)
        channel.setMethodCallHandler({
            (call, result) -> Void in
                switch call.method {
                case "setWindowTheme":
                    let arg = call.arguments as! [String: Any]
                    let themeName = arg["themeName"] as? String
                    guard let window = registrar.view?.window else {
                        result(nil)
                        return
                    }
                    self.setWindowInterfaceMode(window: window,themeName: themeName ?? "light")
                    result(nil)
                    break;
                case "terminate":
                    NSApplication.shared.terminate(self)
                    result(nil)
                case "canRecordAudio":
                    switch AVCaptureDevice.authorizationStatus(for: .audio) {
                    case .authorized:
                        result(1)
                        break
                    case .notDetermined:
                        result(0)
                        break
                    default:
                        result(-1)
                        break
                    }
                case "requestRecordAudio":
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: { granted in
                        DispatchQueue.main.async {
                            result(granted)
                        }
                    })
                    break
                case "bumpMouse":
                    var dx = 0
                    var dy = 0

                    if let argMap = call.arguments as? [String: Any] {
                        dx = (argMap["dx"] as? Int) ?? 0
                        dy = (argMap["dy"] as? Int) ?? 0
                    }
                    else if let argList = call.arguments as? [Any] {
                        dx = argList.count >= 1 ? (argList[0] as? Int) ?? 0 : 0
                        dy = argList.count >= 2 ? (argList[1] as? Int) ?? 0 : 0
                    }

                    var mouseLoc: CGPoint

                    if let dummyEvent = CGEvent(source: nil) { // can this ever fail?
                        mouseLoc = dummyEvent.location
                    }
                    else if let screenFrame = NSScreen.screens.first?.frame {
                        // NeXTStep: Origin is lower-left of primary screen, positive is up
                        // Cocoa Core Graphics: Origin is upper-left of primary screen, positive is down
                        let nsMouseLoc = NSEvent.mouseLocation

                        mouseLoc = CGPoint(
                            x: nsMouseLoc.x,
                            y: NSHeight(screenFrame) - nsMouseLoc.y)
                    }
                    else {
                        result(false)
                        break
                    }

                    let newLoc = CGPoint(x: mouseLoc.x + CGFloat(dx), y: mouseLoc.y + CGFloat(dy))

                    CGDisplayMoveCursorToPoint(0, newLoc)

                    // By default, Cocoa suppresses mouse events briefly after a call to warp the
                    // cursor to a new location. This is good if you want to draw the user's
                    // attention to the fact that the mouse is now in a particular location, but
                    // it's bad in this case; we get called as part of the handling of edge
                    // scrolling, which means the mouse is typically still in motion, and we want
                    // the cursor to keep moving smoothly uninterrupted.
                    //
                    // This function's main action is to toggle whether the mouse cursor is
                    // associated with the mouse position, but setting it to true when it's
                    // already true has the side-effect of cancelling this motion suppression.
                    //
                    // However, we must NOT call this when relative mouse mode is active,
                    // as it would break the pointer lock established by enableNativeRelativeMouseMode.
                    if !RelativeMouseState.shared.enabled {
                        CGAssociateMouseAndMouseCursorPosition(1 /* true */)
                    }

                    result(true)

                case "enableNativeRelativeMouseMode":
                    let success = self.enableNativeRelativeMouseMode(channel: channel)
                    result(success)

                case "disableNativeRelativeMouseMode":
                    self.disableNativeRelativeMouseMode()
                    result(true)

                default:
                    result(FlutterMethodNotImplemented)
                }
        })
    }
}
