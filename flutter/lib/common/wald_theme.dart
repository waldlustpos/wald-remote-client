// Waldlust(DSK-07): 어드민(웹)과 같은 톤의 디자인 토큰.
//
// 값은 어드민 실사이트 CSS(Tailwind v4 neutral·green·red·amber·blue)에서 옮겼다.
// neutral 800·950 과 red 950 은 어드민 CSS 에 없어 Tailwind 기본값으로 보탰다(다크 모드용).
// 주요 버튼과 강조(선택·진행·켜진 토글·체크)는 검정(neutral900), 링크는 본문색 + 밑줄이다(어드민과 같다).
// 파랑(blue600·700)은 어드민 팔레트와 짝을 맞추려고 남겨 둘 뿐 쓰지 않는다(2026-10-15 — 명세 부록 A-27).
// blue200 은 입력칸 글자 선택 영역에만 쓴다(2026-10-22 — 부록 A-53, 회색 선택이 입력칸 바탕과 구분되지 않았다).
// amber700 은 2026-10-21 UI-03(부록 A-49)으로 양쪽 팔레트에 더했다 — 작은 경고 글씨용(흰 바탕 대비 5.05:1, amber600 은 3.2:1).
// 값 = 어드민 빌드(Lightning CSS)가 Tailwind v4 amber-700 oklch 에 내보내는 hex 대체값 — 다른 색과 같은 규칙이다.
// 다크 모드는 보류다(MyTheme.getThemeModePreference) — 다크 값은 다시 도입할 때를 위해 남긴다.
// 이 파일은 common.dart 를 import 하지 않는다(common.dart 가 이 파일을 쓴다).
import 'package:flutter/material.dart';

class WaldPalette {
  WaldPalette._();

  static const Color white = Color(0xFFFFFFFF);

  static const Color neutral50 = Color(0xFFFAFAFA);
  static const Color neutral100 = Color(0xFFF5F5F5);
  static const Color neutral200 = Color(0xFFE5E5E5);
  static const Color neutral300 = Color(0xFFD4D4D4);
  static const Color neutral400 = Color(0xFFA1A1A1);
  static const Color neutral500 = Color(0xFF737373);
  static const Color neutral600 = Color(0xFF525252);
  static const Color neutral700 = Color(0xFF404040);
  static const Color neutral800 = Color(0xFF262626);
  static const Color neutral900 = Color(0xFF171717);
  static const Color neutral950 = Color(0xFF0A0A0A);

  static const Color green50 = Color(0xFFF0FDF4);
  static const Color green100 = Color(0xFFDCFCE7);
  static const Color green500 = Color(0xFF00C758);
  static const Color green600 = Color(0xFF00A544);
  static const Color green700 = Color(0xFF008138);

  static const Color red50 = Color(0xFFFEF2F2);
  static const Color red200 = Color(0xFFFFCACA);
  static const Color red500 = Color(0xFFFB2C36);
  static const Color red600 = Color(0xFFE40014);
  static const Color red700 = Color(0xFFBF000F);
  static const Color red950 = Color(0xFF460809);

  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber500 = Color(0xFFF99C00);
  static const Color amber600 = Color(0xFFDD7400);
  static const Color amber700 = Color(0xFFB75000);

  static const Color blue200 = Color(0xFFBEDBFF);
  static const Color blue600 = Color(0xFF155DFC);
  static const Color blue700 = Color(0xFF1447E6);

  // 알파 변형(const 문맥에서 쓰인다).
  static const Color blue600a77 = Color(0x77155DFC);
  static const Color blue600aAA = Color(0xAA155DFC);
  static const Color neutral900a77 = Color(0x77171717);
  static const Color neutral900aAA = Color(0xAA171717);
  static const Color neutral200a80 = Color(0x80E5E5E5);
  static const Color neutral800a80 = Color(0x80262626);
}

class WaldSize {
  WaldSize._();

  static const double radius = 8;
  static const double cardRadius = 12; // 어드민 카드(rounded-xl)
  static const double dialogRadius = 16;
  static const double buttonHeight = 32;
  static const double buttonFont = 14;
  static const double smallFont = 12;
  static const double iconSm = 16;
  static const double icon = 18;
  static const double iconLg = 20;
}

/// 라이트·다크에 따라 달라지는 어드민 톤 색. `WaldColors.of(context)` 로 읽는다.
class WaldColors extends ThemeExtension<WaldColors> {
  const WaldColors({
    required this.primaryBg,
    required this.primaryFg,
    required this.secondaryBorder,
    required this.headerBg,
  });

  /// 주요 버튼 바탕·글자(테마 버튼을 쓰지 않는 버튼용, 예: 연결 관리 창).
  final Color primaryBg;
  final Color primaryFg;

  /// 보조(테두리) 버튼 테두리.
  final Color secondaryBorder;

  /// 어두운 띠 바탕(연결 관리 창 머리, 홈 화면 안내 카드). 글자는 흰색.
  final Color headerBg;

  static const light = WaldColors(
    primaryBg: WaldPalette.neutral900,
    primaryFg: WaldPalette.white,
    secondaryBorder: WaldPalette.neutral300,
    headerBg: WaldPalette.neutral900,
  );

  static const dark = WaldColors(
    primaryBg: WaldPalette.neutral100,
    primaryFg: WaldPalette.neutral900,
    secondaryBorder: WaldPalette.neutral700,
    headerBg: WaldPalette.neutral800,
  );

  static WaldColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<WaldColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  WaldColors copyWith({
    Color? primaryBg,
    Color? primaryFg,
    Color? secondaryBorder,
    Color? headerBg,
  }) {
    return WaldColors(
      primaryBg: primaryBg ?? this.primaryBg,
      primaryFg: primaryFg ?? this.primaryFg,
      secondaryBorder: secondaryBorder ?? this.secondaryBorder,
      headerBg: headerBg ?? this.headerBg,
    );
  }

  @override
  WaldColors lerp(ThemeExtension<WaldColors>? other, double t) {
    if (other is! WaldColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return WaldColors(
      primaryBg: l(primaryBg, other.primaryBg),
      primaryFg: l(primaryFg, other.primaryFg),
      secondaryBorder: l(secondaryBorder, other.secondaryBorder),
      headerBg: l(headerBg, other.headerBg),
    );
  }
}

/// 어드민 카드(흰 바탕 · neutral200 1px 테두리 · 둥글기 12 · 그림자 없음 — `rounded-xl border bg-white`).
/// 설정 화면 섹션에 쓴다(부록 A-27 — 전에는 M2 Card 의 회색 바탕 + 그림자).
BoxDecoration waldCardDecoration() => BoxDecoration(
      color: WaldPalette.white,
      border: Border.all(color: WaldPalette.neutral200),
      borderRadius: BorderRadius.circular(WaldSize.cardRadius),
    );

/// 데스크탑 입력 칸. 채움색은 기존처럼 바탕과 같은 톤으로 두어 테두리 없는 칸(홈 화면 ID·비밀번호 등)이
/// 바탕에 묻히게 하고, 테두리만 어드민처럼 연한 회색 · 포커스는 진한 색 · 오류는 빨강으로 둔다.
InputDecorationTheme waldInputTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final idle = dark ? WaldPalette.neutral700 : WaldPalette.neutral300;
  final disabled = dark ? WaldPalette.neutral800 : WaldPalette.neutral200;
  final focus = dark ? WaldPalette.neutral300 : WaldPalette.neutral900;
  final error = dark ? WaldPalette.red500 : WaldPalette.red600;
  Color stateColor(Set<WidgetState> states) {
    if (states.contains(WidgetState.error)) return error;
    if (states.contains(WidgetState.focused)) return focus;
    if (states.contains(WidgetState.disabled)) return disabled;
    return idle;
  }

  return InputDecorationTheme(
    fillColor: dark ? WaldPalette.neutral900 : WaldPalette.neutral100,
    filled: true,
    isDense: true,
    border: MaterialStateOutlineInputBorder.resolveWith(
      (states) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(WaldSize.radius),
        borderSide: BorderSide(color: stateColor(states)),
      ),
    ),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith(
      (states) => TextStyle(
          color: states.contains(WidgetState.error) ||
                  states.contains(WidgetState.focused)
              ? stateColor(states)
              : null),
    ),
  );
}

const _kButtonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(WaldSize.radius)));
const _kButtonTextStyle =
    TextStyle(fontSize: WaldSize.buttonFont, fontWeight: FontWeight.w500);

/// 버튼 라벨용 StrutStyle. 한글만 있는 라벨은 대체 글꼴(macOS Apple SD Gothic Neo)의 줄 상자로
/// 놓여 약 0.064em 위로 뜬다(그 글꼴의 ascent/descent 가 비대칭). 줄 상자를 기본 글꼴(SF·Segoe UI)
/// 기준으로 고정하면(forceStrutHeight) 한글·영문 모두 세로 가운데에 온다. TextStyle.height 로는
/// 고쳐지지 않는다(여백이 늘어도 치우침은 그대로다). fontSize 는 라벨 글자 크기와 같아야 한다.
StrutStyle waldButtonStrut([double fontSize = WaldSize.buttonFont]) =>
    StrutStyle(
      fontSize: fontSize,
      height: 1.25,
      leadingDistribution: TextLeadingDistribution.even,
      forceStrutHeight: true,
    );

/// 버튼 공통 모양: 모서리 8, 글자 14·500, 여백 16×6, 최소 64×32, 아이콘 16, 그림자 없음.
/// 데스크탑은 압축 밀도(28px·세로 여백 0)를 쓰지 않는다.
ButtonStyle _waldButtonBase({required bool desktop}) => ButtonStyle(
      shape: const WidgetStatePropertyAll(_kButtonShape),
      textStyle: const WidgetStatePropertyAll(_kButtonTextStyle),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
      minimumSize:
          const WidgetStatePropertyAll(Size(64, WaldSize.buttonHeight)),
      iconSize: const WidgetStatePropertyAll(WaldSize.iconSm),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      visualDensity: desktop ? VisualDensity.standard : null,
      splashFactory: desktop ? NoSplash.splashFactory : null,
    );

WidgetStateProperty<Color?> _waldOverlay(Color base,
        {double hover = 0.08, double pressed = 0.14}) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return base.withOpacity(pressed);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return base.withOpacity(hover);
      }
      return null;
    });

/// 주요 버튼: 라이트 검정 바탕·흰 글자, 다크 밝은 회색 바탕·검정 글자.
/// 마우스를 올린 상태는 오버레이로 표현해, 바탕색만 바꾼 호출부에서도 반응이 남는다.
ButtonStyle waldElevatedStyle(Brightness brightness, {required bool desktop}) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? WaldPalette.neutral100 : WaldPalette.neutral900;
  final fg = dark ? WaldPalette.neutral900 : WaldPalette.white;
  return _waldButtonBase(desktop: desktop).copyWith(
    backgroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.disabled) ? bg.withOpacity(0.5) : bg),
    foregroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.disabled) ? fg.withOpacity(0.7) : fg),
    overlayColor: dark
        ? _waldOverlay(Colors.black, hover: 0.10, pressed: 0.16)
        : _waldOverlay(Colors.white, hover: 0.16, pressed: 0.24),
  );
}

/// 보조(테두리) 버튼: 라이트 흰 바탕·n300 테두리, 다크 n900 바탕·n700 테두리.
ButtonStyle waldOutlinedStyle(Brightness brightness, {required bool desktop}) {
  final dark = brightness == Brightness.dark;
  final fg = dark ? WaldPalette.neutral100 : WaldPalette.neutral900;
  final disabledFg = dark ? WaldPalette.neutral600 : WaldPalette.neutral400;
  final side = dark ? WaldPalette.neutral700 : WaldPalette.neutral300;
  final disabledSide = dark ? WaldPalette.neutral800 : WaldPalette.neutral200;
  return _waldButtonBase(desktop: desktop).copyWith(
    backgroundColor: WidgetStatePropertyAll(
        dark ? WaldPalette.neutral900 : WaldPalette.white),
    foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? disabledFg : fg),
    side: WidgetStateProperty.resolveWith((states) => BorderSide(
        color: states.contains(WidgetState.disabled) ? disabledSide : side)),
    overlayColor: _waldOverlay(fg, hover: 0.05, pressed: 0.10),
  );
}

/// 위험 동작(삭제 등) 버튼: 빨강 바탕·흰 글자. 라이트·다크 같다.
ButtonStyle waldDangerStyle() => ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? WaldPalette.red600.withOpacity(0.5)
              : WaldPalette.red600),
      foregroundColor: const WidgetStatePropertyAll(WaldPalette.white),
      overlayColor: _waldOverlay(Colors.black, hover: 0.10, pressed: 0.16),
    );
