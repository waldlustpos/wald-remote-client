import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/common/widgets/wald_app_info.dart';
import 'package:flutter_hbb/desktop/widgets/wald_account_button.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  bool get isChatPageCurrentTab => isAndroid
      ? _selectedIndex == _chatPageTabIndex
      : false; // change this when ios have chat page

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
  }

  void initPages() {
    _pages.clear();
    // Waldlust(DSK-02): 수신 전용은 화면 공유를 첫 탭, 채팅을 두 번째 탭으로 두고 설정 잠금이면
    // 설정 탭을 뺀다. 채팅 탭 번호를 1로 가정하는 코드(chat_model, server_page)와도 맞는다.
    if (isAndroid && bind.isIncomingOnly()) {
      _pages.add(ServerPage());
      _chatPageTabIndex = _pages.length;
      _pages.add(ChatPage(type: ChatPageType.mobileMain));
      if (!bind.isDisableSettings()) _pages.add(SettingsPage());
      return;
    }
    // Waldlust(DSK-12 — 부록 A-57): 폰은 하단 탭 없이 연결 화면 하나 — 로그인은 앱바 왼쪽, 설정은 오른쪽 버튼.
    // 폰은 원격을 받지 않으므로 양방향 빌드의 채팅·화면 공유 탭도 두지 않는다.
    if (_waldPhoneHome) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
      return;
    }
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
    }
    if (isAndroid && !bind.isOutgoingOnly()) {
      _chatPageTabIndex = _pages.length;
      _pages.addAll([ChatPage(type: ChatPageType.mobileMain), ServerPage()]);
    }
    _pages.add(SettingsPage());
  }

  // Waldlust(DSK-12 — 부록 A-57): 수신 전용(키오스크)이 아닌 모바일 홈 = 폰.
  bool get _waldPhoneHome => !bind.isIncomingOnly();
  bool get _waldShowAccount => _waldPhoneHome && !bind.isDisableAccount();

  // 설정은 하단 탭 대신 새 화면으로 연다(설정 탭에 있던 QR 스캔 버튼은 그 화면 앱바로).
  Widget _waldSettingsButton() {
    return IconButton(
      tooltip: translate('Settings'),
      icon: Icon(waldIcon(Icons.settings)),
      onPressed: () {
        final page = SettingsPage();
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => Scaffold(
                      backgroundColor: Theme.of(context).colorScheme.background,
                      appBar: AppBar(
                        centerTitle: true,
                        title: Text(page.title),
                        actions: page.appBarActions,
                      ),
                      body: page,
                    )));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          // Waldlust(DSK-07): 어드민 톤 — 회색 바탕 위 흰 카드(데스크탑 홈 왼쪽 패널과 같은 색).
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
            centerTitle: true,
            // Waldlust(DSK-12 — 부록 A-57): 데스크탑(부록 A-45)처럼 로그인 상태 버튼.
            leadingWidth: _waldShowAccount ? 140 : null,
            leading: _waldShowAccount
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: WaldAccountButton(
                        height: kToolbarHeight, maxTextWidth: 96))
                : null,
            title: appTitle(),
            actions: [
              ..._pages.elementAt(_selectedIndex).appBarActions,
              // Waldlust(DSK-07 — 부록 A-38): 수신 전용은 설정 탭이 없어 버전 등을 여기서 본다.
              if (isAndroid && bind.isIncomingOnly()) waldAppInfoButton(),
              if (_waldPhoneHome) _waldSettingsButton(),
            ],
          ),
          // Waldlust(DSK-07): 하단 탭은 흰 바탕 + 위 경계선(그림자 없음), 선택된 탭만 파랑.
          // navigationBarKey 는 안쪽 BottomNavigationBar 에 둔다(다른 곳에서 캐스팅한다).
          // DSK-12(부록 A-57): 폰은 하단 탭이 없다(navigationBarKey 를 읽는 곳은 null 을 견딘다).
          bottomNavigationBar: _waldPhoneHome
              ? null
              : Container(
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: MyTheme.color(context).border3!))),
            child: BottomNavigationBar(
              key: navigationBarKey,
              items: _pages
                  .map((page) => BottomNavigationBarItem(
                      icon: page.icon, label: page.title))
                  .toList(),
              currentIndex: _selectedIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
              selectedItemColor: MyTheme.accent, //
              unselectedItemColor: WaldPalette.neutral500,
              onTap: (index) => setState(() {
                // close chat overlay when go chat page
                if (_selectedIndex != index) {
                  _selectedIndex = index;
                  if (isChatPageCurrentTab) {
                    gFFI.chatModel.hideChatIconOverlay();
                    gFFI.chatModel.hideChatWindowOverlay();
                    gFFI.chatModel.mobileClearClientUnread(
                        gFFI.chatModel.currentKey.connId);
                  }
                }
              }),
            ),
          ),
          body: _pages.elementAt(_selectedIndex),
        ));
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              waldIcon(currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded),
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Waldlust(DSK-07): 받은 접속(수신)은 접속한 쪽 이름 없이 ID 만(부록 A-31).
                  Text(
                    currentKey.isOut
                        ? "${currentUser.firstName}   ${currentUser.id}"
                        : currentUser.id,
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: WaldPalette.green500),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    // Waldlust(DSK-10 — 부록 A-38): 수신 전용은 APP_NAME(`Waldlust`) 대신 런처와 같은 이름.
    if (isAndroid && bind.isIncomingOnly()) return Text(kWaldAppDisplayName);
    return Text(bind.mainGetAppNameSync());
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      // backgroundColor: MyTheme.grayBg,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id, 
        isFileTransfer: isFileTransfer, 
        isViewCamera: isViewCamera, 
        isTerminal: isTerminal,
        password: password);
    }
  }
}
