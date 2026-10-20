// Waldlust(DSK-02 — 부록 A-44, 결정 D40): 수신 전용 Android 홈의 '자동 복구' 카드.
// - 도우미 앱: 앱 정보에서 강제 종료한 채 재부팅해도 원격을 다시 켜는 작은 앱(아이콘 없음). 이 앱 안에 넣어 둔 설치 파일로
//   설치를 유도한다(MainActivity 'wald_helper_install' — 시스템 설치 창). 없거나 이 앱에 든 것보다 옛 버전이면, 서비스가 켜진 뒤
//   앱을 연 동안 한 번 설치를 권한다.
// - adb 1회 설정: 강제 종료 뒤 입력 제어(접근성)를 다시 켜는 권한(WRITE_SECURE_SETTINGS — 결정 D38). 앱이 스스로 얻을 수 없어
//   명령을 보여 준다.
// - 입력 제어(도우미) — 2단계(결정 D41): 도우미 접근성이 켜져 있으면 앱을 강제 종료해도 입력 제어가 남아 adb 1회 설정이 필요 없다.
//   도우미에 그 기능이 있으면 줄을 보이고, 켜져 있으면 adb 줄은 숨긴다.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import '../pages/server_page.dart' show PaddingCard;

/// MainActivity 가 설치 결과를 알리면(server_page.dart androidChannelInit 'wald_helper_changed') 카드가 상태를 다시 읽는다.
final waldHelperChanged = ValueNotifier<int>(0);

const kWaldAdbGrantCommand =
    'adb shell pm grant co.kr.waldlust.remote android.permission.WRITE_SECURE_SETTINGS';

/// 앱을 연 동안(프로세스) 한 번만 설치를 권한다.
bool _waldHelperPrompted = false;

/// 앱을 연 동안(프로세스) 한 번만 도우미 입력 제어를 켜라고 권한다.
bool _waldHelperInputPrompted = false;

/// 도우미에 입력 제어 기능이 있다(마지막으로 읽은 값) — 입력 제어 안내(server_model.dart showInputWarnAlert)가 도우미 항목을 가리킨다.
bool waldHelperInputCapable = false;

class _WaldHelperStatus {
  final bool installed;
  final bool hasBundle;
  final bool needsUpdate;
  final bool adbGranted;
  final bool inputCapable;
  final bool inputOn;

  const _WaldHelperStatus(this.installed, this.hasBundle, this.needsUpdate,
      this.adbGranted, this.inputCapable, this.inputOn);

  bool get helperOk => installed && !needsUpdate;

  static Future<_WaldHelperStatus?> fetch() async {
    try {
      final m = await platformFFI.invokeMethod('wald_helper_status');
      if (m is! Map) return null;
      waldHelperInputCapable = m['inputCapable'] == true;
      return _WaldHelperStatus(
          m['installed'] == true,
          m['hasBundle'] == true,
          m['needsUpdate'] == true,
          m['adbGranted'] == true,
          m['inputCapable'] == true,
          m['inputOn'] == true);
    } catch (e) {
      debugPrint('wald_helper_status: $e');
      return null;
    }
  }
}

class WaldHelperCard extends StatefulWidget {
  const WaldHelperCard({Key? key}) : super(key: key);

  @override
  State<WaldHelperCard> createState() => _WaldHelperCardState();
}

class _WaldHelperCardState extends State<WaldHelperCard>
    with WidgetsBindingObserver {
  _WaldHelperStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    waldHelperChanged.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    waldHelperChanged.removeListener(_refresh);
    super.dispose();
  }

  // 시스템 설치 창·'출처를 알 수 없는 앱' 설정에서 돌아오면 다시 읽는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _WaldHelperStatus.fetch();
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  Future<void> _install() async {
    setState(() => _busy = true);
    final r = await platformFFI.invokeMethod('wald_helper_install');
    if (!mounted) return;
    if (r == 'settings') {
      showToast(translate('wald-helper-allow-source-tip'),
          timeout: const Duration(seconds: 6));
    } else if (r == 'no_bundle') {
      showToast(translate('wald-helper-no-bundle-tip'));
    } else if (r != 'started') {
      showToast(translate('wald-helper-install-failed-tip'));
    }
    if (r != 'started') setState(() => _busy = false);
  }

  void _openAccessibilitySettings() {
    AndroidPermissionManager.startAction(kActionAccessibilitySettings);
  }

  // 도우미가 최신인데 도우미 입력 제어가 꺼져 있고 adb 설정도 없으면 한 번 켜라고 권한다(adb 가 있으면 앱이 켠다).
  void _maybePromptInput(_WaldHelperStatus status, bool serviceRunning) {
    if (_waldHelperInputPrompted ||
        !serviceRunning ||
        !status.helperOk ||
        !status.inputCapable ||
        status.inputOn ||
        status.adbGranted) {
      return;
    }
    _waldHelperInputPrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
            title: Text(translate('wald-helper-input-prompt-title')),
            content: Text(translate('wald-helper-input-prompt-tip')),
            actions: [
              dialogButton('wald-helper-later',
                  onPressed: close, isOutline: true),
              dialogButton('wald-helper-input-open', onPressed: () {
                close();
                _openAccessibilitySettings();
              }),
            ],
            onCancel: close,
          ));
    });
  }

  // 서비스가 켜진 뒤(첫 설치의 권한·서비스 시작과 겹치지 않게) 한 번 권한다.
  void _maybePrompt(_WaldHelperStatus status, bool serviceRunning) {
    if (_waldHelperPrompted ||
        !serviceRunning ||
        !status.hasBundle ||
        status.helperOk) {
      _maybePromptInput(status, serviceRunning);
      return;
    }
    _waldHelperPrompted = true;
    final update = status.installed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
            title: Text(translate(update
                ? 'wald-helper-update-title'
                : 'wald-helper-prompt-title')),
            content: Text(translate('wald-helper-prompt-tip')),
            actions: [
              dialogButton('wald-helper-later',
                  onPressed: close, isOutline: true),
              dialogButton(
                  update ? 'wald-helper-update' : 'wald-helper-install',
                  onPressed: () {
                close();
                _install();
              }),
            ],
            onCancel: close,
          ));
    });
  }

  Widget _row(
      {required bool ok,
      required String title,
      required String tip,
      Widget? extra,
      Widget? action}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(waldIcon(ok ? Icons.check_circle : Icons.warning_amber_sharp),
              size: 20,
              color: ok ? WaldPalette.green600 : WaldPalette.amber600)
          .marginOnly(right: 10, top: 2),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(tip, style: const TextStyle(fontSize: 12, color: MyTheme.darkGray))
            .marginOnly(top: 2),
        if (extra != null) extra.marginOnly(top: 4),
        if (action != null) action.marginOnly(top: 8),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    _maybePrompt(status, serverModel.isStart);
    final helperTip = !status.installed
        ? (status.hasBundle
            ? 'wald-helper-missing-tip'
            : 'wald-helper-no-bundle-tip')
        : (status.needsUpdate
            ? 'wald-helper-update-tip'
            : 'wald-helper-installed-tip');
    return PaddingCard(
        title: translate('wald-helper-card-title'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(
            ok: status.helperOk,
            title: translate('wald-helper-row'),
            tip: translate(helperTip),
            action: !status.helperOk && status.hasBundle
                ? ElevatedButton.icon(
                    icon: Icon(waldIcon(Icons.download)),
                    onPressed: _busy ? null : _install,
                    label: Text(
                        translate(status.installed
                            ? 'wald-helper-update'
                            : 'wald-helper-install'),
                        strutStyle: waldButtonStrut()))
                : null,
          ),
          if (status.installed && status.inputCapable) ...[
            const SizedBox(height: 14),
            _row(
              ok: status.inputOn,
              title: translate('wald-helper-input-row'),
              tip: translate(status.inputOn
                  ? 'wald-helper-input-on-tip'
                  : 'wald-helper-input-off-tip'),
              action: status.inputOn
                  ? null
                  : ElevatedButton.icon(
                      icon: Icon(waldIcon(Icons.settings)),
                      onPressed: _openAccessibilitySettings,
                      label: Text(translate('wald-helper-input-open'),
                          strutStyle: waldButtonStrut())),
            ),
          ],
          if (!(status.inputCapable && status.inputOn)) ...[
            const SizedBox(height: 14),
            _row(
              ok: status.adbGranted,
              title: translate('wald-adb-row'),
              tip: translate(status.adbGranted
                  ? 'wald-adb-ok-tip'
                  : 'wald-adb-missing-tip'),
              extra: status.adbGranted
                  ? null
                  : const SelectableText(kWaldAdbGrantCommand,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ]));
  }
}
