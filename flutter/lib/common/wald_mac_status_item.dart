import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';
import '../models/platform_model.dart';
import '../utils/multi_window_manager.dart';
import 'widgets/wald_app_info.dart';

// Waldlust(DSK-07, 부록 A-41): macOS 메뉴 막대(상단 바) 아이콘(열기·종료)과 창을 닫아도 원격 서비스를
// 유지하는 백그라운드 상태. 아이콘 자체는 네이티브(flutter/macos/Runner/MainFlutterWindow.swift
// WaldStatusItem)가 그리고, 이 클래스는 메인 창 엔진에서 보일지·라벨을 정하고 '열기'를 처리한다.
// 서비스가 이 앱 프로세스 안에서 도는 동안(서비스 중지가 아니고 설치형 서비스가 아님)만 아이콘을 띄우고,
// 그때만 마지막 창을 닫아도 앱을 끝내지 않는다(Dock 아이콘도 숨김). '종료'는 네이티브가 앱을 끝낸다.
class WaldMacStatusItem {
  static const _channel = MethodChannel('co.kr.waldlust/status_item');

  static bool? _visible;
  static bool? _installedDaemon;
  static Uint8List? _icon;
  static bool _inBackground = false;

  static bool get visible => _visible == true;

  static void init() {
    if (!isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') await open();
    });
  }

  /// desktop_home_page 의 1초 갱신에서 부른다. 보일지가 바뀔 때만 네이티브에 알린다.
  static Future<void> sync({required bool serviceRunning}) async {
    if (!isMacOS) return;
    // 설치형 서비스(LaunchAgent `--server`)면 그 프로세스가 src/tray.rs 트레이를 띄우므로 겹치지 않게 한다.
    _installedDaemon ??= bind.mainIsInstalledDaemon(prompt: false);
    final v = serviceRunning && !_installedDaemon!;
    if (v == _visible) return;
    _visible = v;
    _icon ??= (await rootBundle.load('assets/mac-tray.png')).buffer.asUint8List();
    await _channel.invokeMethod('update', {
      'visible': v,
      'icon': _icon,
      'tooltip': '$kWaldAppDisplayName - ${translate('Service is running')}',
      'open': translate('Open'),
      'quit': translate('Quit'),
    });
  }

  /// 앱 안 업데이트(명세 DSK-01): 번들을 바꾼 뒤 메뉴 막대 '종료'와 같이 끝낸다(src/wald_update.rs 가 새 앱을 연다).
  static Future<void> quit() => _channel.invokeMethod('quit');

  static Future<void> open() async {
    // Dock 아이콘을 먼저 되살려야 창을 앞으로 가져올 때 앱 메뉴도 함께 돌아온다.
    await windowManager.setSkipTaskbar(false);
    await windowOnTop(null);
  }

  /// common.dart onActiveWindowChanged() 가 먼저 부른다. true 면 앱을 끝내지 않고 백그라운드로 뒀다.
  static Future<bool> onActiveWindowChanged() async {
    if (!isMacOS) return false;
    if (rustDeskWinManager.getActiveWindows().isNotEmpty) {
      // 백그라운드에서 원격 링크 등으로 창이 열리면 Dock 아이콘을 되살린다.
      if (_inBackground) {
        _inBackground = false;
        await windowManager.setSkipTaskbar(false);
      }
      return false;
    }
    if (!visible) return false;
    _inBackground = true;
    await rustDeskWinManager.closeAllSubWindows();
    await windowManager.setSkipTaskbar(true);
    return true;
  }
}
