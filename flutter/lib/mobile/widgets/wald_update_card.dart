// Waldlust(DSK-01 — 결정 D44, 부록 A-62): 수신 전용 Android 홈의 '새 버전' 카드.
// 확인·받기는 Rust(src/wald_update.rs — 받기 키), 확인 창·진행·오류는 데스크탑과 같은 대화상자(desktop/widgets/wald_update.dart),
// 설치는 Kotlin(WaldSelfUpdate.kt — 시스템 설치 창, 사람이 [업데이트]를 누른다). 새 버전이 있을 때만 보인다.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../desktop/widgets/wald_update.dart';
import '../../models/state_model.dart';
import '../pages/server_page.dart' show PaddingCard;

class WaldUpdateCard extends StatelessWidget {
  const WaldUpdateCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // common.dart checkUpdate 가 확인 결과(status available)일 때만 채운다.
      final version = stateGlobal.waldUpdateVersion.value;
      if (version.isEmpty) return const SizedBox.shrink();
      return PaddingCard(
        title: translate('wald-update-title'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(translate('wald-update-{$version}-tip')),
          ElevatedButton.icon(
                  icon: Icon(waldIcon(Icons.download)),
                  onPressed: showWaldUpdateDialog,
                  label:
                      Text(translate('Update'), strutStyle: waldButtonStrut()))
              .marginOnly(top: 8),
        ]),
      );
    });
  }
}
