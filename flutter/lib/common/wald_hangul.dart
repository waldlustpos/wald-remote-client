// Waldlust(UI-03 — 명세 부록 A-49): 로그인·접속 비밀번호 칸은 일반 웹 로그인처럼 영문·숫자·기호·공백(U+0020~U+007E)만
// 받고, 한글과 Caps Lock 을 칸 아래에 알린다. 어드민 app/components/AsciiInput.tsx 와 같은 규칙·문구다.
// DSK-03(부록 A-32 — 한글이 들어오면 안내만 하고 로그인 요청을 보내지 않음)을 대체한다.
//
// OS·브라우저의 비밀번호 칸은 한글 입력기를 꺼서 한글 모드에서도 영문이 들어간다. Flutter 입력 칸은 그러지 않아
// 한글 모드로 친 비밀번호가 한글로 들어간다(칸에는 ●만 보여 이유를 모른다).
// 조합 중인 구간(입력기가 아직 확정하지 않은 글자)은 고치지 않는다 — 입력 칸이 그 구간을 바꾸면 입력기 상태와 어긋난다
// (글자 중복·누락). 그 밖의 허용 밖 글자는 곧바로 버리고, 조합 중이던 글자는 확정되는 순간 버린다.
// 그래서 조합이 끝나기 전에 제출하면(Enter 는 입력기 확정보다 먼저 온다) 값에 한글이 남는다 — 제출하는 곳에서 waldIsAscii 로 막는다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../common.dart';

const kWaldPasswordHangulTip = 'wald-password-hangul-tip';
const kWaldPasswordCapsLockTip = 'wald-password-capslock-tip';

bool _allowed(int unit) => unit >= 0x20 && unit <= 0x7E;

/// [s] 가 허용 글자(U+0020~U+007E)만인지.
bool waldIsAscii(String s) => s.codeUnits.every(_allowed);

/// 허용 밖 글자를 버리는 포매터. 조합 중인 구간은 그대로 둔다(파일 머리 주석).
/// [onHangul] 은 안내를 켤 때 true(버렸거나 조합 중인 글자가 허용 밖), 허용 글자만 새로 들어왔을 때 false 로 불린다.
class WaldAsciiFormatter extends TextInputFormatter {
  WaldAsciiFormatter(this.onHangul);

  final ValueChanged<bool> onHangul;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final composing = newValue.composing;
    final hasComposing = composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length;
    final kept = <int>[];
    // removed[i] = i 앞에서 버린 글자 수(커서·조합 구간 위치를 옮길 때 쓴다).
    final removed = List<int>.filled(text.length + 1, 0);
    var composingAllowed = true;
    for (var i = 0; i < text.length; i++) {
      removed[i + 1] = removed[i];
      final unit = text.codeUnitAt(i);
      final inComposing =
          hasComposing && i >= composing.start && i < composing.end;
      if (inComposing) {
        if (!_allowed(unit)) composingAllowed = false;
        kept.add(unit);
      } else if (_allowed(unit)) {
        kept.add(unit);
      } else {
        removed[i + 1]++;
      }
    }
    final dropped = removed[text.length] > 0;
    if (dropped || !composingAllowed) {
      onHangul(true);
    } else if (text.length > oldValue.text.length) {
      onHangul(false);
    }
    if (!dropped) return newValue;
    int move(int offset) =>
        offset < 0 ? offset : offset - removed[offset.clamp(0, text.length)];
    return TextEditingValue(
      text: String.fromCharCodes(kept),
      selection: newValue.selection.copyWith(
        baseOffset: move(newValue.selection.baseOffset),
        extentOffset: move(newValue.selection.extentOffset),
      ),
      composing: hasComposing
          ? TextRange(start: move(composing.start), end: move(composing.end))
          : TextRange.empty,
    );
  }
}

/// 영문만 받는 입력 칸과 칸 아래 안내. [builder] 는 받은 포매터를 입력 칸의 inputFormatters 에 넣는다.
/// [capsLock] 이면(비밀번호 칸) 칸에 포커스가 있는 동안 Caps Lock 이 켜져 있으면 알린다 — 입력은 막지 않는다.
class WaldAsciiInput extends StatefulWidget {
  const WaldAsciiInput({Key? key, required this.builder, this.capsLock = false})
      : super(key: key);

  final Widget Function(TextInputFormatter formatter) builder;
  final bool capsLock;

  @override
  State<WaldAsciiInput> createState() => _WaldAsciiInputState();
}

class _WaldAsciiInputState extends State<WaldAsciiInput> {
  late final WaldAsciiFormatter _formatter = WaldAsciiFormatter((on) {
    if (on != _hangul && mounted) setState(() => _hangul = on);
  });
  bool _hangul = false;
  bool _focused = false;
  bool _capsLock = false;

  bool _capsLockOn() => HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.capsLock);

  // 잠금 키 상태는 키 입력 때마다 갱신된다(HardwareKeyboard). 키를 먹지 않는다.
  bool _onKey(KeyEvent _) {
    final on = _capsLockOn();
    if (on != _capsLock && mounted) setState(() => _capsLock = on);
    return false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.capsLock) {
      _capsLock = _capsLockOn();
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  Widget _tip(String key) => Text(
        translate(key),
        style: const TextStyle(color: WaldPalette.amber600, fontSize: 12),
      ).paddingOnly(left: 12, bottom: 4);

  @override
  Widget build(BuildContext context) {
    // 트리 모양을 늘 같게 둔다 — 바뀌면 입력 칸이 새로 만들어져 포커스·조합 상태를 잃는다.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) {
            if (mounted) setState(() => _focused = focused);
          },
          child: widget.builder(_formatter),
        ),
        if (_hangul) _tip(kWaldPasswordHangulTip),
        if (widget.capsLock && _focused && _capsLock)
          _tip(kWaldPasswordCapsLockTip),
      ],
    );
  }
}
