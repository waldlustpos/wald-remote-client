import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = Icon(waldIcon(Icons.connected_tv));

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // Waldlust(DSK-12): 연결 화면 맨 위에 보여 주는 내 ID.
  final RxString _waldMyId = ''.obs;

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    if (isMobile) bind.mainGetMyId().then((id) => _waldMyId.value = id);
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return CustomScrollView(
      slivers: [
        SliverList(
            delegate: SliverChildListDelegate([
          if (!bind.isCustomClient() && !isIOS)
            Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
          if (isMobile) _buildWaldMyId(),
          _buildRemoteIDTextField(),
        ])),
        SliverFillRemaining(
          hasScrollBody: true,
          // Waldlust(DSK-07): 회색 바탕 위 흰 패널(피어 탭의 n100 검색칸·카드가 묻히지 않게).
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(WaldSize.radius),
              border: Border.all(color: MyTheme.color(context).border3!),
            ),
            child: PeerTabPage(),
          ),
        )
      ],
    ).marginOnly(top: 2, left: 10, right: 10);
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect({bool isFileTransfer = false}) {
    var id = _idController.id;
    connect(context, id, isFileTransfer: isFileTransfer);
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    return updateUrl.isEmpty
        ? const SizedBox(height: 0)
        : InkWell(
            onTap: () async {
              final url = 'https://rustdesk.com/download';
              // https://pub.dev/packages/url_launcher#configuration
              // https://developer.android.com/training/package-visibility/use-cases#open-urls-custom-tabs
              //
              // `await launchUrl(Uri.parse(url))` can also run if skip
              // 1. The following check
              // 2. `<action android:name="android.support.customtabs.action.CustomTabsService" />` in AndroidManifest.xml
              //
              // But it is better to add the check.
              await launchUrl(Uri.parse(url));
            },
            child: Container(
                alignment: AlignmentDirectional.center,
                width: double.infinity,
                color: Colors.pinkAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(translate('Download new version'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))));
  }

  // Waldlust(DSK-12): 폰은 원격을 받지 않으니 내 ID 는 보기만 한다(어드민 기기 목록과 맞춰 보는 용도) — 복사만 둔다.
  // 높이는 ID 를 받기 전부터 잡아 둔다 — 줄이 뒤늦게 생겨 아래 카드가 밀리면 카드의 Ink 바탕만 옛 자리에 남는다.
  Widget _buildWaldMyId() {
    return Obx(() {
      final id = _waldMyId.value;
      return SizedBox(
        height: 36,
        child: id.isEmpty
            ? null
            : Row(
                children: [
                  Text(translate('My ID'),
                      style: const TextStyle(
                          fontSize: 13, color: WaldPalette.neutral500)),
                  const SizedBox(width: 8),
                  Text(formatID(id),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: WaldPalette.neutral900,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    color: WaldPalette.neutral500,
                    icon: Icon(waldIcon(Icons.copy_outlined)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: id));
                      showToast(translate('Copied'));
                    },
                  ),
                ],
              ).paddingOnly(left: 6),
      );
    });
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemoteIDTextField() {
    final w = SizedBox(
      height: 84,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Ink(
          // Waldlust(DSK-07): 어드민 톤 카드 — 흰 바탕·모서리 8·테두리.
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.all(Radius.circular(WaldSize.radius)),
            border: Border.all(color: MyTheme.color(context).border3!),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 16, right: 16),
                  child: RawAutocomplete<Peer>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        _autocompleteOpts = const Iterable<Peer>.empty();
                      } else if (_allPeersLoader.peers.isEmpty &&
                          !_allPeersLoader.isPeersLoaded) {
                        Peer emptyPeer = Peer(
                          id: '',
                          username: '',
                          hostname: '',
                          alias: '',
                          platform: '',
                          tags: [],
                          hash: '',
                          password: '',
                          forceAlwaysRelay: false,
                          rdpPort: '',
                          rdpUsername: '',
                          loginName: '',
                          device_group_name: '',
                          note: '',
                        );
                        _autocompleteOpts = [emptyPeer];
                      } else {
                        String textWithoutSpaces =
                            textEditingValue.text.replaceAll(" ", "");
                        if (int.tryParse(textWithoutSpaces) != null) {
                          textEditingValue = TextEditingValue(
                            text: textWithoutSpaces,
                            selection: textEditingValue.selection,
                          );
                        }
                        String textToFind = textEditingValue.text.toLowerCase();

                        _autocompleteOpts = _allPeersLoader.peers
                            .where((peer) =>
                                peer.id.toLowerCase().contains(textToFind) ||
                                peer.username
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.hostname
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.alias.toLowerCase().contains(textToFind))
                            .toList();
                        _allPeersLoader.queryOnlines(_autocompleteOpts);
                      }
                      return _autocompleteOpts;
                    },
                    focusNode: _idFocusNode,
                    textEditingController: _idEditingController,
                    fieldViewBuilder: (BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted) {
                      updateTextAndPreserveSelection(
                          fieldTextEditingController, _idController.text);
                      return AutoSizeTextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        minFontSize: 18,
                        autocorrect: false,
                        enableSuggestions: false,
                        // Waldlust(DSK-12): 원격 ID 는 숫자만 받는다(숫자 키패드). 공백은 IDTextInputFormatter 가 세 자리마다 넣는다.
                        keyboardType: TextInputType.number,
                        // Waldlust(DSK-12): 칸 밖을 누르면 키패드를 내린다(iOS 숫자 키패드에는 닫기 키가 없다).
                        // 자동완성 목록은 같은 탭 영역(TextFieldTapRegion)이라 항목 선택은 그대로 된다.
                        onTapOutside: (_) => fieldFocusNode.unfocus(),
                        onChanged: (String text) {
                          _idController.id = text;
                        },
                        style: const TextStyle(
                          fontFamily: 'WorkSans',
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                        ),
                        decoration: InputDecoration(
                          // Waldlust(DSK-12): 라벨 대신 힌트 — 비어 있을 때만 보이고 입력하면 사라진다. labelText 는 띄우지
                          // 않아도 위에 떠 있는 라벨 자리를 남겨 글자·커서가 카드 가운데보다 아래로 내려갔다.
                          hintText: translate('Remote ID'),
                          border: InputBorder.none,
                          // Waldlust(DSK-07): 테마 입력 칸의 채움색을 쓰지 않는다(카드 안 큰 ID 칸).
                          filled: false,
                          helperStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: MyTheme.darkGray,
                          ),
                          hintStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: 0.2,
                            color: MyTheme.darkGray,
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                          IDTextInputFormatter()
                        ],
                        onSubmitted: (_) {
                          onConnect();
                        },
                      );
                    },
                    onSelected: (option) {
                      setState(() {
                        _idController.id = option.id;
                        FocusScope.of(context).unfocus();
                      });
                    },
                    optionsViewBuilder: (BuildContext context,
                        AutocompleteOnSelected<Peer> onSelected,
                        Iterable<Peer> options) {
                      options = _autocompleteOpts;
                      double maxHeight = options.length * 50;
                      if (options.length == 1) {
                        maxHeight = 52;
                      } else if (options.length == 3) {
                        maxHeight = 146;
                      } else if (options.length == 4) {
                        maxHeight = 193;
                      }
                      maxHeight = maxHeight.clamp(0, 200);
                      return Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Material(
                                      elevation: 4,
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: maxHeight,
                                            maxWidth: 320,
                                          ),
                                          child: _allPeersLoader
                                                      .peers.isEmpty &&
                                                  !_allPeersLoader.isPeersLoaded
                                              ? Container(
                                                  height: 80,
                                                  child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  )))
                                              : ListView(
                                                  padding:
                                                      EdgeInsets.only(top: 5),
                                                  children: options
                                                      .map((peer) =>
                                                          AutocompletePeerTile(
                                                              onSelect: () =>
                                                                  onSelected(
                                                                      peer),
                                                              peer: peer))
                                                      .toList(),
                                                ))))));
                    },
                  ),
                ),
              ),
              Obx(() => Offstage(
                    offstage: _idEmpty.value,
                    child: IconButton(
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                          });
                        },
                        icon: Icon(waldIcon(Icons.clear),
                            color: MyTheme.darkGray)),
                  )),
              // Waldlust(DSK-07): 데스크탑 [연결] 과 같은 주요(검정) 버튼.
              // DSK-12: 아이콘·순서를 데스크탑([연결] → [파일 전송])과 같게.
              SizedBox.square(
                dimension: 44,
                child: Tooltip(
                  message: translate('Connect'),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(44)),
                    onPressed: onConnect,
                    child: Icon(waldIcon(Icons.screen_share_outlined),
                        size: WaldSize.iconLg),
                  ),
                ),
              ).marginOnly(right: 8),
              // Waldlust(DSK-12, 부록 A-48): 데스크탑처럼 파일 전송을 보조(테두리) 버튼으로 꺼낸다.
              SizedBox.square(
                dimension: 44,
                child: Tooltip(
                  message: translate('Transfer file'),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(44)),
                    onPressed: () => onConnect(isFileTransfer: true),
                    child: Icon(waldIcon(Icons.folder_outlined),
                        size: WaldSize.iconLg),
                  ),
                ),
              ).marginOnly(right: 12),
            ],
          ),
        ),
      ),
    );
    final child = Column(children: [
      if (isWebDesktop)
        getConnectionPageTitle(context, true)
            .marginOnly(bottom: 10, top: 15, left: 12),
      w
    ]);
    return Align(
        alignment: Alignment.topCenter,
        child: Container(constraints: kMobilePageConstraints, child: child));
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}
