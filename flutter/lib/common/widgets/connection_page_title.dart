import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';

Widget getConnectionPageTitle(BuildContext context, bool isWeb) {
  return Row(
    children: [
      Expanded(
          child: Row(
        children: [
          AutoSizeText(
            translate('Control Remote Desktop'),
            maxLines: 1,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.merge(TextStyle(height: 1)),
          ).marginOnly(right: 4),
          // Waldlust(DSK-07, 부록 A-53): 제목 옆 '?'(마우스를 올리면 RustDesk 서버 주소 문법 안내
          // id_input_tip·web_id_input_tip, 클릭 동작 없음)는 사내 사용자에게 필요 없어 뺐다.
        ],
      )),
    ],
  );
}
