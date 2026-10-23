import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/login.dart';
import '../../consts.dart';

// Waldlust(DSK-03 — 명세 부록 A-45): 메인 창 앱바의 설정 버튼 왼쪽 계정 버튼.
// 로그인 여부가 한눈에 보이게 아이콘과 글자를 함께 둔다 — 미로그인 = 회색 사람 아이콘 + '로그인',
// 로그인 = 검정 원 아이콘 + 계정 이름. 누르면 미로그인은 로그인 대화상자, 로그인은 계정 정보 대화상자.
// DSK-12(부록 A-57): 폰 홈 앱바 왼쪽에도 쓴다 — 높이·이름 최대 너비만 바꿔 넘긴다.
class WaldAccountButton extends StatelessWidget {
  final double height;
  final double maxTextWidth;
  const WaldAccountButton(
      {Key? key,
      this.height = kDesktopRemoteTabBarHeight - 1,
      this.maxTextWidth = 160})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userModel = gFFI.userModel;
    final tabbar = MyTheme.tabbar(context);
    return Obx(() {
      final login = userModel.isLogin;
      return Tooltip(
        message: login ? userModel.userName.value : translate('Login'),
        waitDuration: const Duration(seconds: 1),
        child: InkWell(
          hoverColor: tabbar.hoverColor,
          onTap: () => login ? showWaldAccountInfo() : loginDialog(),
          child: SizedBox(
            height: height,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              login
                  ? _avatar(size: 20, iconSize: 13)
                  : Icon(waldIcon(Icons.person_outline),
                      size: WaldSize.iconLg, color: tabbar.unSelectedIconColor),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTextWidth),
                child: Text(
                  login ? userModel.displayNameOrUserName : translate('Login'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: isMobile ? 14 : 13,
                      color: login
                          ? tabbar.selectedTextColor
                          : tabbar.unSelectedTextColor),
                ),
              ).marginOnly(left: 6),
            ]).paddingSymmetric(horizontal: 10),
          ),
        ),
      );
    });
  }
}

Widget _avatar({required double size, required double iconSize}) {
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
        color: WaldPalette.neutral900, shape: BoxShape.circle),
    child: Icon(waldIcon(Icons.person), size: iconSize, color: Colors.white),
  );
}

/// 로그인한 계정 정보(이름·아이디)와 로그아웃.
void showWaldAccountInfo() {
  final userModel = gFFI.userModel;
  final name = userModel.displayNameOrUserName;
  final handle = userModel.userName.value;
  gFFI.dialogManager.show((setState, close, context) {
    logout() {
      close();
      userModel.logOut();
    }

    return CustomAlertDialog(
      title: Text(translate('Account')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _avatar(size: 44, iconSize: 24),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (handle != name)
                  SelectableText(handle,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 13, color: WaldPalette.neutral500))
                      .marginOnly(top: 2),
              ],
            ).marginOnly(left: 12),
          ),
        ]),
      ),
      actions: [
        dialogButton('Logout', onPressed: logout, isOutline: true),
        dialogButton('Close', onPressed: close),
      ],
      onCancel: close,
    );
  }, backDismiss: true, clickMaskDismiss: true);
}
