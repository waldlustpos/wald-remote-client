// Waldlust(DSK-07): 아이콘 세트를 Lucide(lucide_icons_flutter, MIT)로 통일한다.
//
// - 굵기는 가는 선 하나 — 굵기 변형 300 글꼴('Lucide300', 선 1.55)만 쓴다. 기본 글꼴('Lucide', 선 2)과
//   다른 변형(x100 … x600)은 섞지 않는다. 2026-10-15 카드 버튼에서 시험한 뒤 사용자 결정으로 앱 전체에 적용했다.
//   이름은 LucideIcons.<이름>300(예: folder300, trash2300).
// - 모든 IconData 는 const 다(릴리스 빌드의 아이콘 글꼴 트리 셰이킹이 그대로 동작한다).
// - 크기: 버튼·메뉴 16, 툴바·파일 목록 18, 탭·연결 관리 창 머리 20(WaldSize).
// - IconFont(common.dart)의 상수도 Lucide 를 가리키므로, IconFont 를 쓰는 곳은 호출부를 고치지
//   않아도 Lucide 로 그려진다.
// - 호출부는 waldIcon(Icons.x) 처럼 Material 이름을 그대로 두고(업스트림 병합 때 원래 아이콘이
//   보이게), Lucide 대응은 아래 표(kWaldLucideFor) 한 곳에 모은다. 표에 없는 아이콘은 Material 그대로다.
// - 플랫폼 로고·로그인 제공자 로고·키보드 배열 그림·연결 보안 배지·화면 번호 SVG 는 유지한다.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/wald_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

export 'package:lucide_icons_flutter/lucide_icons.dart' show LucideIcons;

/// Material → Lucide 대응. IconData 는 == 를 재정의해 const Map 키로 쓸 수 없어 final 로 둔다
/// (키·값은 모두 const 라 릴리스 빌드의 아이콘 글꼴 트리 셰이킹은 그대로 동작한다).
final Map<IconData, IconData> kWaldLucideFor = {
  Icons.network_ping_outlined: LucideIcons.activity300,
  Icons.network_ping: LucideIcons.activity300,
  Icons.web_asset_outlined: LucideIcons.appWindow300,
  Icons.sort_rounded: LucideIcons.arrowDownWideNarrow300,
  Icons.sort: LucideIcons.arrowDownWideNarrow300,
  Icons.arrow_back: LucideIcons.arrowLeft300,
  Icons.arrow_back_rounded: LucideIcons.arrowLeft300,
  Icons.compare_arrows: LucideIcons.arrowLeftRight300,
  Icons.arrow_forward: LucideIcons.arrowRight300,
  Icons.arrow_forward_rounded: LucideIcons.arrowRight300,
  Icons.arrow_forward_sharp: LucideIcons.arrowRight300,
  Icons.arrow_upward: LucideIcons.arrowUp300,
  Icons.block: LucideIcons.ban300,
  Icons.check: LucideIcons.check300,
  Icons.done: LucideIcons.check300,
  Icons.done_rounded: LucideIcons.check300,
  Icons.arrow_drop_down: LucideIcons.chevronDown300,
  Icons.expand_more: LucideIcons.chevronDown300,
  Icons.expand_more_sharp: LucideIcons.chevronDown300,
  Icons.keyboard_arrow_down: LucideIcons.chevronDown300,
  Icons.keyboard_arrow_down_rounded: LucideIcons.chevronDown300,
  Icons.arrow_back_ios: LucideIcons.chevronLeft300,
  Icons.arrow_left: LucideIcons.chevronLeft300,
  Icons.chevron_left: LucideIcons.chevronLeft300,
  Icons.keyboard_arrow_left: LucideIcons.chevronLeft300,
  Icons.arrow_forward_ios: LucideIcons.chevronRight300,
  Icons.arrow_right: LucideIcons.chevronRight300,
  Icons.chevron_right: LucideIcons.chevronRight300,
  Icons.keyboard_arrow_right: LucideIcons.chevronRight300,
  Icons.keyboard_arrow_right_rounded: LucideIcons.chevronRight300,
  Icons.navigate_next_rounded: LucideIcons.chevronRight300,
  Icons.expand_less: LucideIcons.chevronUp300,
  Icons.keyboard_arrow_up_rounded: LucideIcons.chevronUp300,
  Icons.keyboard_arrow_up: LucideIcons.chevronUp300,
  Icons.error_outline: LucideIcons.circleAlert300,
  Icons.error: LucideIcons.circleAlert300,
  Icons.check_circle: LucideIcons.circleCheck300,
  Icons.help: LucideIcons.circleHelp300,
  Icons.help_outline: LucideIcons.circleHelp300,
  Icons.help_outline_outlined: LucideIcons.circleHelp300,
  Icons.pause_circle_filled: LucideIcons.circlePause300,
  Icons.stop: LucideIcons.circleStop300,
  Icons.cancel: LucideIcons.circleX300,
  Icons.cancel_outlined: LucideIcons.circleX300,
  Icons.assignment_rounded: LucideIcons.clipboardList300,
  Icons.paste: LucideIcons.clipboardPaste300,
  Icons.input: LucideIcons.clipboardPaste300,
  Icons.query_builder: LucideIcons.clock300,
  Icons.cloud: LucideIcons.cloud300,
  Icons.cloud_off: LucideIcons.cloudOff300,
  Icons.cloud_upload: LucideIcons.cloudUpload300,
  Icons.explore: LucideIcons.compass300,
  Icons.copy: LucideIcons.copy300,
  Icons.copy_outlined: LucideIcons.copy300,
  Icons.download: LucideIcons.download300,
  Icons.more_vert: LucideIcons.ellipsisVertical300,
  Icons.more_vert_outlined: LucideIcons.ellipsisVertical300,
  Icons.launch_outlined: LucideIcons.externalLink300,
  Icons.visibility: LucideIcons.eye300,
  Icons.visibility_off: LucideIcons.eyeOff300,
  Icons.file_copy_outlined: LucideIcons.files300,
  Icons.file_copy_sharp: LucideIcons.files300,
  Icons.fingerprint: LucideIcons.fingerprint300,
  Icons.folder_outlined: LucideIcons.folder300,
  Icons.drive_file_move_outlined: LucideIcons.folderInput300,
  Icons.folder_open: LucideIcons.folderOpen300,
  Icons.create_new_folder: LucideIcons.folderPlus300,
  Icons.forward_sharp: LucideIcons.forward300,
  Icons.forward_outlined: LucideIcons.forward300,
  Icons.sentiment_very_dissatisfied_rounded: LucideIcons.frown300,
  Icons.drag_handle: LucideIcons.gripHorizontal300,
  Icons.drag_indicator: LucideIcons.gripVertical300,
  Icons.access_time_filled: LucideIcons.history300,
  Icons.hourglass_top: LucideIcons.hourglass300,
  Icons.home: LucideIcons.house300,
  Icons.home_outlined: LucideIcons.house300,
  Icons.home_sharp: LucideIcons.house300,
  Icons.home_filled: LucideIcons.house300,
  Icons.perm_identity: LucideIcons.idCard300,
  Icons.image_search: LucideIcons.image300,
  Icons.info: LucideIcons.info300,
  Icons.info_outline: LucideIcons.info300,
  Icons.info_outline_rounded: LucideIcons.info300,
  Icons.key: LucideIcons.key300,
  Icons.password_rounded: LucideIcons.keyRound300,
  Icons.keyboard: LucideIcons.keyboard300,
  Icons.translate: LucideIcons.languages300,
  Icons.apps_rounded: LucideIcons.layoutGrid300,
  Icons.grid_view_rounded: LucideIcons.layoutGrid300,
  Icons.link: LucideIcons.link300,
  Icons.link_outlined: LucideIcons.link300,
  Icons.view_list_rounded: LucideIcons.list300,
  Icons.select_all: LucideIcons.listChecks300,
  Icons.lock_outline: LucideIcons.lock300,
  Icons.no_encryption_outlined: LucideIcons.lockOpen300,
  Icons.login_rounded: LucideIcons.logIn300,
  Icons.logout_rounded: LucideIcons.logOut300,
  Icons.email: LucideIcons.mail300,
  Icons.fullscreen: LucideIcons.maximize300,
  Icons.chat: LucideIcons.messageSquare300,
  Icons.chat_bubble_outline: LucideIcons.messageSquare300,
  Icons.message: LucideIcons.messageSquare300,
  Icons.fullscreen_exit: LucideIcons.minimize300,
  Icons.remove: LucideIcons.minus300,
  Icons.computer: LucideIcons.monitor300,
  Icons.connected_tv: LucideIcons.monitor300,
  Icons.desktop_windows: LucideIcons.monitor300,
  Icons.desktop_windows_outlined: LucideIcons.monitor300,
  Icons.desktop_windows_sharp: LucideIcons.monitor300,
  Icons.tv: LucideIcons.monitor300,
  Icons.dark_mode: LucideIcons.moon300,
  Icons.mouse: LucideIcons.mouse300,
  Icons.lan_outlined: LucideIcons.network300,
  Icons.edit: LucideIcons.pencil300,
  Icons.edit_rounded: LucideIcons.pencil300,
  Icons.edit_outlined: LucideIcons.pencil300,
  Icons.call_rounded: LucideIcons.phone300,
  Icons.phone: LucideIcons.phone300,
  Icons.call_received_rounded: LucideIcons.phoneIncoming300,
  Icons.call_end_rounded: LucideIcons.phoneOff300,
  Icons.phone_disabled_rounded: LucideIcons.phoneOff300,
  Icons.call_made_rounded: LucideIcons.phoneOutgoing300,
  Icons.push_pin: LucideIcons.pin300,
  Icons.play_arrow: LucideIcons.play300,
  Icons.add: LucideIcons.plus300,
  Icons.add_rounded: LucideIcons.plus300,
  Icons.touch_app: LucideIcons.pointer300,
  Icons.print: LucideIcons.printer300,
  Icons.print_outlined: LucideIcons.printer300,
  Icons.extension: LucideIcons.puzzle300,
  Icons.extension_outlined: LucideIcons.puzzle300,
  Icons.refresh: LucideIcons.refreshCw300,
  Icons.refresh_rounded: LucideIcons.refreshCw300,
  Icons.reply: LucideIcons.reply300,
  Icons.restart_alt_rounded: LucideIcons.rotateCcw300,
  Icons.view_agenda_rounded: LucideIcons.rows2300,
  Icons.qr_code_scanner: LucideIcons.scanQrCode300,
  Icons.mobile_screen_share: LucideIcons.screenShare300,
  Icons.screen_share_outlined: LucideIcons.screenShare300,
  Icons.screen_share: LucideIcons.screenShare300,
  Icons.search_rounded: LucideIcons.search300,
  Icons.send_rounded: LucideIcons.send300,
  Icons.dns_outlined: LucideIcons.server300,
  Icons.build_outlined: LucideIcons.settings300,
  Icons.build_sharp: LucideIcons.settings300,
  Icons.settings: LucideIcons.settings300,
  Icons.settings_outlined: LucideIcons.settings300,
  Icons.privacy_tip: LucideIcons.shield300,
  Icons.admin_panel_settings: LucideIcons.shieldCheck300,
  Icons.enhanced_encryption: LucideIcons.shieldCheck300,
  Icons.enhanced_encryption_outlined: LucideIcons.shieldCheck300,
  Icons.security_rounded: LucideIcons.shieldCheck300,
  Icons.security_sharp: LucideIcons.shieldCheck300,
  Icons.security: LucideIcons.shieldCheck300,
  Icons.phone_android_sharp: LucideIcons.smartphone300,
  Icons.crop_square: LucideIcons.square300,
  Icons.check_box_outline_blank: LucideIcons.square300,
  Icons.check_box: LucideIcons.squareCheck300,
  Icons.check_box_outlined: LucideIcons.squareCheck300,
  Icons.terminal: LucideIcons.squareTerminal300,
  Icons.terminal_outlined: LucideIcons.squareTerminal300,
  Icons.star: LucideIcons.star300,
  Icons.star_outline: LucideIcons.star300,
  Icons.light_mode: LucideIcons.sun300,
  Icons.switch_camera: LucideIcons.switchCamera300,
  Icons.tag: LucideIcons.tag300,
  Icons.tag_rounded: LucideIcons.tag300,
  Icons.delete: LucideIcons.trash2300,
  Icons.delete_forever: LucideIcons.trash2300,
  Icons.delete_outline: LucideIcons.trash2300,
  Icons.delete_outline_rounded: LucideIcons.trash2300,
  Icons.delete_rounded: LucideIcons.trash2300,
  Icons.warning_amber_rounded: LucideIcons.triangleAlert300,
  Icons.warning_amber_sharp: LucideIcons.triangleAlert300,
  Icons.warning_rounded: LucideIcons.triangleAlert300,
  Icons.link_off_rounded: LucideIcons.unlink300,
  Icons.upload: LucideIcons.upload300,
  Icons.upload_file_rounded: LucideIcons.upload300,
  Icons.account_circle_outlined: LucideIcons.user300,
  Icons.person: LucideIcons.user300,
  Icons.person_outline: LucideIcons.user300,
  Icons.group: LucideIcons.users300,
  Icons.videocam_outlined: LucideIcons.video300,
  Icons.videocam_rounded: LucideIcons.video300,
  Icons.volume_up_rounded: LucideIcons.volume2300,
  Icons.build: LucideIcons.wrench300,
  Icons.clear: LucideIcons.x300,
  Icons.close: LucideIcons.x300,
  Icons.close_rounded: LucideIcons.x300,
  Icons.flash_on: LucideIcons.zap300,
};

/// [material] 의 Lucide 대응을 돌려준다(대응이 없으면 [material] 그대로).
IconData waldIcon(IconData material) => kWaldLucideFor[material] ?? material;

/// [widget] 이 대응표에 있는 Material 아이콘이면 같은 크기·색의 Lucide 아이콘으로 바꾼다.
Widget? waldLucideIconWidget(Widget? widget) {
  if (widget is Icon) {
    final icon = widget.icon;
    final lucide = icon == null ? null : kWaldLucideFor[icon];
    if (lucide != null) {
      return Icon(lucide,
          size: widget.size,
          color: widget.color,
          semanticLabel: widget.semanticLabel);
    }
  }
  return widget;
}

/// SVG 아이콘(원격 툴바·파일 전송·연결 관리 창) → Lucide. 없는 항목은 SVG 를 그대로 쓴다.
const Map<String, IconData> kWaldAssetIcon = {
  // 원격 툴바
  'assets/pinned.svg': LucideIcons.pin300,
  'assets/unpinned.svg': LucideIcons.pinOff300,
  'assets/actions.svg': LucideIcons.zap300,
  'assets/actions_mobile.svg': LucideIcons.smartphone300,
  'assets/display.svg': LucideIcons.monitor300,
  'assets/keyboard_mouse.svg': LucideIcons.keyboard300,
  'assets/chat.svg': LucideIcons.messageSquare300,
  'assets/message_24dp_5F6368.svg': LucideIcons.messageSquareText300,
  'assets/voice_call.svg': LucideIcons.phone300,
  'assets/call_wait.svg': LucideIcons.phoneCall300,
  'assets/rec.svg': LucideIcons.circleDot300,
  'assets/close.svg': LucideIcons.x300,
  // 파일 전송(arrow 는 오른쪽 화살표를 돌려 뒤로·위로·보내기·받기에 쓴다)
  'assets/arrow.svg': LucideIcons.arrowRight300,
  'assets/refresh.svg': LucideIcons.refreshCw300,
  'assets/search.svg': LucideIcons.search300,
  'assets/home.svg': LucideIcons.house300,
  'assets/folder_new.svg': LucideIcons.folderPlus300,
  'assets/trash.svg': LucideIcons.trash2300,
  'assets/dots.svg': LucideIcons.ellipsisVertical300,
  'assets/transfer.svg': LucideIcons.arrowLeftRight300,
  'assets/file.svg': LucideIcons.file300,
  'assets/folder.svg': LucideIcons.folder300,
  // 연결 관리 창
  'assets/chat2.svg': LucideIcons.messageSquare300,
  'assets/file_transfer.svg': LucideIcons.arrowLeftRight300,
};

/// [asset] SVG 를 대신할 Lucide 아이콘. 대응이 없으면 null(SVG 를 그대로 쓴다).
IconData? waldAssetIcon(String asset) => kWaldAssetIcon[asset];

/// 파일 전송 목록의 확장자(소문자, 점 없이) → 파일 종류 아이콘(부록 A-36). 없는 확장자는 [LucideIcons.file300].
const Map<String, IconData> kWaldFileTypeIcon = {
  // 이미지
  'png': LucideIcons.fileImage300,
  'jpg': LucideIcons.fileImage300,
  'jpeg': LucideIcons.fileImage300,
  'gif': LucideIcons.fileImage300,
  'bmp': LucideIcons.fileImage300,
  'webp': LucideIcons.fileImage300,
  'heic': LucideIcons.fileImage300,
  'svg': LucideIcons.fileImage300,
  'ico': LucideIcons.fileImage300,
  'tif': LucideIcons.fileImage300,
  'tiff': LucideIcons.fileImage300,
  // 영상
  'mp4': LucideIcons.filePlay300,
  'mov': LucideIcons.filePlay300,
  'avi': LucideIcons.filePlay300,
  'mkv': LucideIcons.filePlay300,
  'wmv': LucideIcons.filePlay300,
  'webm': LucideIcons.filePlay300,
  'm4v': LucideIcons.filePlay300,
  // 음악
  'mp3': LucideIcons.fileMusic300,
  'wav': LucideIcons.fileMusic300,
  'flac': LucideIcons.fileMusic300,
  'aac': LucideIcons.fileMusic300,
  'm4a': LucideIcons.fileMusic300,
  'ogg': LucideIcons.fileMusic300,
  'wma': LucideIcons.fileMusic300,
  // 압축
  'zip': LucideIcons.fileArchive300,
  'rar': LucideIcons.fileArchive300,
  '7z': LucideIcons.fileArchive300,
  'tar': LucideIcons.fileArchive300,
  'gz': LucideIcons.fileArchive300,
  'tgz': LucideIcons.fileArchive300,
  'bz2': LucideIcons.fileArchive300,
  'xz': LucideIcons.fileArchive300,
  // 표
  'xls': LucideIcons.fileSpreadsheet300,
  'xlsx': LucideIcons.fileSpreadsheet300,
  'csv': LucideIcons.fileSpreadsheet300,
  'ods': LucideIcons.fileSpreadsheet300,
  'numbers': LucideIcons.fileSpreadsheet300,
  // 문서
  'txt': LucideIcons.fileText300,
  'md': LucideIcons.fileText300,
  'log': LucideIcons.fileText300,
  'rtf': LucideIcons.fileText300,
  'pdf': LucideIcons.fileText300,
  'doc': LucideIcons.fileText300,
  'docx': LucideIcons.fileText300,
  'hwp': LucideIcons.fileText300,
  'hwpx': LucideIcons.fileText300,
  'odt': LucideIcons.fileText300,
  'pages': LucideIcons.fileText300,
  // 코드
  'js': LucideIcons.fileCode300,
  'ts': LucideIcons.fileCode300,
  'dart': LucideIcons.fileCode300,
  'rs': LucideIcons.fileCode300,
  'py': LucideIcons.fileCode300,
  'java': LucideIcons.fileCode300,
  'c': LucideIcons.fileCode300,
  'cpp': LucideIcons.fileCode300,
  'h': LucideIcons.fileCode300,
  'sh': LucideIcons.fileCode300,
  'html': LucideIcons.fileCode300,
  'css': LucideIcons.fileCode300,
  // 설정
  'ini': LucideIcons.fileCog300,
  'cfg': LucideIcons.fileCog300,
  'conf': LucideIcons.fileCog300,
  'json': LucideIcons.fileCog300,
  'xml': LucideIcons.fileCog300,
  'yaml': LucideIcons.fileCog300,
  'yml': LucideIcons.fileCog300,
  'toml': LucideIcons.fileCog300,
  'reg': LucideIcons.fileCog300,
  // 실행·설치
  'exe': LucideIcons.fileBox300,
  'msi': LucideIcons.fileBox300,
  'bat': LucideIcons.fileBox300,
  'cmd': LucideIcons.fileBox300,
  'com': LucideIcons.fileBox300,
  'ps1': LucideIcons.fileBox300,
  'apk': LucideIcons.fileBox300,
  'dmg': LucideIcons.fileBox300,
  'pkg': LucideIcons.fileBox300,
  'deb': LucideIcons.fileBox300,
  'rpm': LucideIcons.fileBox300,
  'app': LucideIcons.fileBox300,
};

/// 파일 전송 목록 항목 아이콘: 드라이브·폴더·확장자별 파일(부록 A-36).
/// 확장자는 마지막 '.' 뒤다('.' 로 시작하는 이름의 첫 점은 확장자로 보지 않는다).
IconData waldFileEntryIcon(String name,
    {bool isDir = false, bool isDrive = false}) {
  if (isDrive) return LucideIcons.hardDrive300;
  if (isDir) return LucideIcons.folder300;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return LucideIcons.file300;
  return kWaldFileTypeIcon[name.substring(dot + 1).toLowerCase()] ??
      LucideIcons.file300;
}

/// 예전 SVG 는 [box] 크기 상자 안에 여백까지 그려져 있었다. 그 자리를 같은 크기 상자 가운데의
/// Lucide 아이콘([size])으로 대신한다.
Widget waldIconBox(IconData icon,
    {double box = 32, double size = WaldSize.icon, Color? color}) {
  return SizedBox.square(
    dimension: box,
    child: Center(child: Icon(icon, size: size, color: color)),
  );
}

/// SvgPicture.asset 대신 쓴다. 대응이 있으면 같은 크기 상자 가운데에 Lucide 를,
/// 아니면 SVG 를 그린다. [color] 는 SVG 에 주던 svgColor(color) 와 같다. 크기를 주지 않으면
/// 예전 SVG 의 기본 크기(32)를 쓰고, 아이콘은 상자의 18/32 크기다(예: 32 → 18).
Widget waldSvg(String asset,
    {Color? color, double? width, double? height, double? iconSize}) {
  final lucide = waldAssetIcon(asset);
  if (lucide == null) {
    return SvgPicture.asset(asset,
        colorFilter:
            color == null ? null : ColorFilter.mode(color, BlendMode.srcIn),
        width: width,
        height: height);
  }
  final w = width ?? height ?? 32;
  final h = height ?? width ?? 32;
  return SizedBox(
    width: w,
    height: h,
    child: Center(
      child: Icon(lucide,
          size: iconSize ?? (w < h ? w : h) * WaldSize.icon / 32, color: color),
    ),
  );
}
