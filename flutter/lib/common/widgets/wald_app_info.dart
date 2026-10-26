import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../desktop/widgets/wald_update.dart';
import '../../models/platform_model.dart';

// Waldlust(DSK-07·DSK-10 — 명세 부록 A-38): 화면에 쓰는 앱 이름. 런처 라벨(AndroidManifest
// android:label)·macOS 번들 이름(AppInfo.xcconfig PRODUCT_NAME)·Windows 시작 메뉴(Inno AppName)와 같다.
// APP_NAME(`Waldlust`)은 설정 폴더·IPC 에 묶여 있어 그대로 둔다(Q-29).
const kWaldAppDisplayName = 'Waldlust 원격지원';

/// 앱바 오른쪽 정보 버튼. 수신 전용 Android 는 설정 탭이 잠겨 있어(disable-settings) 버전을 볼 곳이 없다.
Widget waldAppInfoButton() {
  return IconButton(
    tooltip: translate('About'),
    icon: Icon(waldIcon(Icons.info_outline)),
    onPressed: showWaldAppInfo,
  );
}

/// Windows 수신 전용 홈의 ID 줄 오른쪽 — 설정(⋮)을 숨긴 자리 — 정보 버튼(부록 A-39).
/// ⋮(desktop_home_page.dart `buildPopupMenu`)와 같은 크기·마우스 올림.
Widget waldDesktopAppInfoButton(BuildContext context) {
  final textColor = Theme.of(context).textTheme.titleLarge?.color;
  final hover = false.obs;
  return InkWell(
    onTap: showWaldAppInfo,
    onHover: (value) => hover.value = value,
    child: Tooltip(
      message: translate('About'),
      child: Obx(
        () => CircleAvatar(
          radius: 15,
          backgroundColor: hover.value
              ? Theme.of(context).scaffoldBackgroundColor
              : Theme.of(context).colorScheme.background,
          child: Icon(
            waldIcon(Icons.info_outline),
            size: 20,
            color: hover.value ? textColor : textColor?.withOpacity(0.5),
          ),
        ),
      ),
    ),
  );
}

/// 앱 이름·버전·빌드 날짜와 공개 고지 링크(데스크탑 설정 '정보'와 같은 항목, 지문은 뺌).
Future<void> showWaldAppInfo() async {
  // 데스크탑은 설정 '정보'와 같은 값(Cargo 버전), Android 는 PackageInfo versionName.
  final appVersion = isDesktop ? await bind.mainGetVersion() : version;
  final buildDate = await bind.mainGetBuildDate();
  gFFI.dialogManager.show((setState, close, context) {
    // Windows 수신 전용 홈은 폭 280·높이 약 390 창이라(부록 A-39) 데스크탑은 간격을 줄이고
    // 값은 한 줄로 둔다(넘치면 조금 줄인다 — 빌드 날짜가 두 줄로 꺾여 저작권 줄이 가려졌다).
    final narrow = isDesktop;
    Widget infoRow(String label, String value) => Row(children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(color: WaldPalette.neutral500))),
          Expanded(
              child: narrow
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, softWrap: false))
                  : SelectableText(value)),
        ]).marginSymmetric(vertical: 4);
    Widget link(String text, String url) => InkWell(
          onTap: () => launchUrlString(url),
          child: Row(children: [
            Text(text,
                style: const TextStyle(decoration: TextDecoration.underline)),
            Icon(waldIcon(Icons.launch_outlined),
                    size: 14, color: WaldPalette.neutral500)
                .marginOnly(left: 4),
          ]).marginSymmetric(vertical: narrow ? 4 : 6),
        );
    return CustomAlertDialog(
      title: Text(kWaldAppDisplayName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          infoRow(translate('Version'), appVersion),
          infoRow(translate('Build Date'), buildDate),
          // Waldlust(DSK-01 — 결정 D44): 수신 전용은 설정이 없어 최신 버전 확인·앱 안 업데이트를 여기 둔다.
          if (waldUpdateSupported && bind.isIncomingOnly())
            const WaldUpdateAboutRow(compact: true),
          Divider(height: narrow ? 16 : 24),
          // Waldlust(D35): 이 앱이 보내는 정보·오픈소스 고지(자사 공개 페이지).
          link(translate('Privacy Statement'), kWaldPrivacyUrl),
          link(translate('Open source notices'), kWaldOssUrl),
          Text(
            // Waldlust(D35 — AGPL §5): 데스크탑 설정 '정보'의 저작권 줄과 같다.
            'Copyright © ${DateTime.now().toString().substring(0, 4)} Purslane Ltd.\n'
            'Modifications © 2026 Waldlust Co., Ltd.\n'
            'Licensed under the GNU AGPL-3.0, without any warranty.',
            style: const TextStyle(fontSize: 11, color: WaldPalette.neutral500),
          ).marginOnly(top: 12),
        ],
      ),
      actions: [dialogButton('Close', onPressed: close)],
      onCancel: close,
      // 바깥 여백도 줄인다(기본 좌우 40·위아래 24).
      insetPadding: narrow
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : null,
    );
  }, backDismiss: true, clickMaskDismiss: true);
}
