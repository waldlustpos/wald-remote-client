import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/wald_mac_status_item.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

// Waldlust 앱 안 업데이트(명세 DSK-01 — 2026-10-23 사용자 결정): 데스크탑 양방향(직원용) macOS·Windows.
// 확인·받기·설치는 Rust(src/wald_update.rs)가 하고, 여기서는 상태(main_get_common 'wald-update-state')를 읽어
// 홈 '새 버전' 카드의 [업데이트] 대화상자와 설정 > 정보의 '최신 버전' 줄을 그린다.
// 받기는 앱 로그인 토큰으로 한다 — 로그인하지 않았으면 로그인을 권하거나 어드민 '원격 설치 파일'을 연다.

bool get waldUpdateSupported =>
    (isWindows || isMacOS) && !bind.isIncomingOnly();

Map<String, dynamic> _readState() {
  try {
    final v = jsonDecode(bind.mainGetCommonSync(key: 'wald-update-state'));
    if (v is Map<String, dynamic>) return v;
  } catch (e) {
    debugPrint('wald update state: $e');
  }
  return {};
}

Map<String, dynamic> _latest(Map<String, dynamic> s) =>
    s['latest'] is Map<String, dynamic> ? s['latest'] : {};

String _str(Map<String, dynamic> m, String k) =>
    m[k] is String ? m[k] as String : '';

/// 지금 확인한다(설정 > 정보). 결과는 'wald_update_state' 이벤트로 stateGlobal 에 들어온다(common.dart checkUpdate).
void waldUpdateCheckNow() {
  stateGlobal.waldUpdateState.value = {
    ...stateGlobal.waldUpdateState.value,
    'status': 'checking'
  };
  bind.mainSetCommon(key: 'wald-update-check', value: '');
}

/// 홈 카드·정보 탭의 [업데이트].
Future<void> showWaldUpdateDialog() async {
  final s = _readState();
  final latest = _latest(s);
  final version = _str(latest, 'version');
  // 확인 중(checking)이어도 지난 확인의 새 버전으로 진행한다.
  if (version.isEmpty || versionCmp(version, _str(s, 'current')) <= 0) return;
  final page = _str(latest, 'page');
  // 해시가 없는 등 앱 안에서 받을 수 없으면 지금처럼 어드민 페이지를 연다.
  if (_str(latest, 'download').isEmpty) {
    if (page.isNotEmpty) launchUrlString(page);
    return;
  }
  if (bind.mainGetLocalOption(key: 'access_token').isEmpty) {
    _showLoginNeeded(page);
    return;
  }
  final subWindows = (await rustDeskWinManager.getAllSubWindowIds()).length;
  final changelog = _str(latest, 'changelog');
  gFFI.dialogManager.dismissAll();
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      close();
      _startUpdate(page);
    }

    return CustomAlertDialog(
      title: Text(translate('wald-update-dialog-title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_str(s, 'current')}  →  $version',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(translate('wald-update-confirm-tip')),
          if (subWindows > 0)
            Text(translate('wald-update-windows-{$subWindows}-tip'))
                .marginOnly(top: 4),
          Text(translate(
                  isWindows ? 'wald-update-uac-tip' : 'wald-update-mac-tip'))
              .marginOnly(top: 4),
          if (changelog.isNotEmpty)
            InkWell(
              onTap: () => launchUrlString(changelog),
              child: Text(translate('wald-update-changelog'),
                  style: const TextStyle(
                      decoration: TextDecoration.underline)),
            ).marginOnly(top: 12),
        ],
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('Update', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

void _showLoginNeeded(String page) {
  gFFI.dialogManager.dismissAll();
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('wald-update-dialog-title')),
      content: Text(translate('wald-update-login-tip')),
      actions: [
        dialogButton('Close', onPressed: close, isOutline: true),
        if (page.isNotEmpty)
          dialogButton('wald-update-open-admin', onPressed: () {
            close();
            launchUrlString(page);
          }, isOutline: true),
        dialogButton('Login', onPressed: () async {
          close();
          if (await loginDialog() == true) showWaldUpdateDialog();
        }),
      ],
      onCancel: close,
    );
  });
}

Future<void> _startUpdate(String page) async {
  await bind.mainSetCommon(key: 'wald-update-start', value: '');
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('wald-update-dialog-title')),
      content: _WaldUpdateProgress(page: page, close: close),
      actions: [
        Obx(() => _job.value['state'] == 'downloading'
            ? dialogButton('Cancel',
                onPressed: () =>
                    bind.mainSetCommon(key: 'wald-update-cancel', value: ''),
                isOutline: true)
            : const SizedBox.shrink()),
      ],
    );
  }, tag: 'wald-update-progress');
}

final _job = Rx<Map<String, dynamic>>({});

class _WaldUpdateProgress extends StatefulWidget {
  final String page;
  final VoidCallback close;
  const _WaldUpdateProgress({required this.page, required this.close});

  @override
  State<_WaldUpdateProgress> createState() => _WaldUpdateProgressState();
}

class _WaldUpdateProgressState extends State<_WaldUpdateProgress> {
  Timer? _timer;
  bool _installSent = false;
  bool _quitSent = false;

  @override
  void initState() {
    super.initState();
    final job = _readState()['job'];
    if (job is Map<String, dynamic>) _job.value = job;
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    final job = _readState()['job'];
    if (job is! Map<String, dynamic>) return;
    _job.value = job;
    switch (job['state']) {
      case 'ready':
        if (!_installSent) {
          _installSent = true;
          bind.mainSetCommon(key: 'wald-update-install', value: '');
        }
        break;
      case 'quit':
        if (!_quitSent) {
          _quitSent = true;
          WaldMacStatusItem.quit();
        }
        break;
      case 'idle': // 받기 취소
        _timer?.cancel();
        widget.close();
        break;
      case 'error':
        _timer?.cancel();
        widget.close();
        _showError(_str(job, 'error'), _str(job, 'detail'), widget.page);
        break;
      case 'installed':
        _timer?.cancel();
        break;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final job = _job.value;
    final state = _str(job, 'state');
    final total = job['total'] is int ? job['total'] as int : 0;
    final done = job['done'] is int ? job['done'] as int : 0;
    String mb(int b) => (b / 1048576).toStringAsFixed(1);
    final String text;
    switch (state) {
      case 'downloading':
        text = total > 0
            ? '${translate('wald-update-downloading')}  ${mb(done)} / ${mb(total)} MB'
            : translate('wald-update-downloading');
        break;
      case 'verifying':
        text = translate('wald-update-verifying');
        break;
      case 'installed':
        text = translate('wald-update-installed-tip');
        break;
      default: // ready·installing·quit
        text = translate(isWindows
            ? 'wald-update-installing-uac-tip'
            : 'wald-update-installing-tip');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state != 'installed')
          LinearProgressIndicator(
            value: state == 'downloading' && total > 0 ? done / total : null,
            minHeight: 20,
            borderRadius: BorderRadius.circular(5),
            backgroundColor: Colors.grey[300],
            valueColor:
                const AlwaysStoppedAnimation<Color>(WaldPalette.neutral900),
          ).paddingOnly(top: 12, bottom: 12),
        Text(text),
        if (state == 'installed')
          dialogButton('Close', onPressed: widget.close)
              .paddingOnly(top: 12),
      ],
    ).marginSymmetric(horizontal: 8);
  }
}

void _showError(String code, String detail, String page) {
  if (code == 'login') {
    _showLoginNeeded(page);
    return;
  }
  gFFI.dialogManager.dismissAll();
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('wald-update-dialog-title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate('wald-update-error-$code')),
          if (detail.isNotEmpty)
            SelectableText(detail,
                    style: const TextStyle(
                        fontSize: 11, color: WaldPalette.neutral500))
                .marginOnly(top: 8),
        ],
      ),
      actions: [
        dialogButton('Close', onPressed: close, isOutline: true),
        if (page.isNotEmpty)
          dialogButton('wald-update-open-admin', onPressed: () {
            close();
            launchUrlString(page);
          }, isOutline: true),
        dialogButton('Retry', onPressed: () {
          close();
          showWaldUpdateDialog();
        }),
      ],
      onCancel: close,
    );
  });
}

/// 설정 > 정보의 '최신 버전' 줄 — 처음 그릴 때 확인한다(1분 안에 확인했으면 그 결과를 쓴다).
class WaldUpdateAboutRow extends StatefulWidget {
  const WaldUpdateAboutRow({super.key});

  @override
  State<WaldUpdateAboutRow> createState() => _WaldUpdateAboutRowState();
}

class _WaldUpdateAboutRowState extends State<WaldUpdateAboutRow> {
  @override
  void initState() {
    super.initState();
    final s = _readState();
    if (s.isNotEmpty) stateGlobal.waldUpdateState.value = s;
    final checkedAt = s['checkedAt'] is int ? s['checkedAt'] as int : 0;
    if (s['status'] != 'checking' &&
        DateTime.now().millisecondsSinceEpoch - checkedAt > 60 * 1000) {
      waldUpdateCheckNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final s = stateGlobal.waldUpdateState.value;
      final status = _str(s, 'status');
      final latest = _latest(s);
      final checkedAt = s['checkedAt'] is int ? s['checkedAt'] as int : 0;
      final changelog = _str(latest, 'changelog');
      final String text;
      switch (status) {
        case 'checking':
          text = translate('wald-update-checking');
          break;
        case 'available':
          text = translate('wald-update-new-{${_str(latest, 'version')}}');
          break;
        case 'latest':
          text = translate('wald-update-is-latest');
          break;
        case 'error':
          text = translate('wald-update-check-failed');
          break;
        default:
          text = '-';
      }
      const linkStyle = TextStyle(decoration: TextDecoration.underline);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${translate('wald-update-latest-label')}: $text',
                style: status == 'available'
                    ? const TextStyle(fontWeight: FontWeight.w600)
                    : null),
            if (status == 'available')
              dialogButton('Update', onPressed: showWaldUpdateDialog)
                  .marginOnly(left: 12),
          ]).marginSymmetric(vertical: 4.0),
          Row(children: [
            if (checkedAt > 0)
              Text(
                '${translate('wald-update-checked-at')}: ${DateTime.fromMillisecondsSinceEpoch(checkedAt).toString().substring(5, 16)}',
                style: const TextStyle(color: WaldPalette.neutral500),
              ).marginOnly(right: 12),
            dialogButton('wald-update-check',
                onPressed: status == 'checking' ? null : waldUpdateCheckNow,
                isOutline: true),
            if (changelog.isNotEmpty)
              InkWell(
                onTap: () => launchUrlString(changelog),
                child: Text(translate('wald-update-changelog'),
                    style: linkStyle),
              ).marginOnly(left: 12),
          ]).marginSymmetric(vertical: 4.0),
        ],
      );
    });
  }
}
