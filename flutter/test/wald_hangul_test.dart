import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/wald_hangul.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _v(String text, {int? caret, TextRange? composing}) =>
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
      composing: composing ?? TextRange.empty,
    );

void main() {
  test('허용 = U+0020~U+007E(영문·숫자·기호·공백)', () {
    expect(waldIsAscii(''), isTrue);
    expect(waldIsAscii('abcd1234'), isTrue);
    expect(waldIsAscii('Ab!@#\$%^&*()_+-=[]{};:\'",.<>/?`~ '), isTrue);
    expect(waldIsAscii('뮻ㅇ1234'), isFalse); // 한글 모드로 친 abcd1234
    expect(waldIsAscii('ㅁ'), isFalse); // 호환 자모(조합 중인 낱자)
    expect(waldIsAscii('ᄆ'), isFalse); // 첫가끝 초성
    expect(waldIsAscii('あ漢'), isFalse);
    expect(waldIsAscii('a\tb'), isFalse); // 탭·줄바꿈 등 제어 문자
    expect(waldIsAscii('😀'), isFalse);
    expect(waldIsAscii(' '), isFalse); // NBSP
  });

  group('WaldAsciiFormatter', () {
    late List<bool> calls;
    late WaldAsciiFormatter f;
    setUp(() {
      calls = [];
      f = WaldAsciiFormatter(calls.add);
    });

    test('영문 입력은 그대로 두고 안내를 거둔다', () {
      final out = f.formatEditUpdate(_v('ab'), _v('abc'));
      expect(out.text, 'abc');
      expect(calls, [false]);
    });

    test('확정된 한글·붙여넣기는 버리고 커서를 옮긴다', () {
      final out = f.formatEditUpdate(_v('a'), _v('a한글b', caret: 3));
      expect(out.text, 'ab');
      expect(out.selection, const TextSelection.collapsed(offset: 1));
      expect(out.composing, TextRange.empty);
      expect(calls, [true]);
    });

    test('조합 중인 구간은 고치지 않고 안내만 켠다', () {
      final out = f.formatEditUpdate(
          _v('1'), _v('1ㅁ', composing: const TextRange(start: 1, end: 2)));
      expect(out.text, '1ㅁ');
      expect(out.composing, const TextRange(start: 1, end: 2));
      expect(calls, [true]);
    });

    test('앞 글자가 확정되고 새 조합이 시작되면 확정된 것만 버린다', () {
      // macOS 2벌식: abcd → '뮻' 확정 + 'ㅇ' 조합.
      final out = f.formatEditUpdate(
          _v('1뮻', composing: const TextRange(start: 1, end: 2)),
          _v('1뮻ㅇ', composing: const TextRange(start: 2, end: 3)));
      expect(out.text, '1ㅇ');
      expect(out.composing, const TextRange(start: 1, end: 2));
      expect(out.selection, const TextSelection.collapsed(offset: 2));
      expect(calls, [true]);
    });

    test('조합이 끝나면(확정) 남은 한글을 버린다', () {
      final out = f.formatEditUpdate(
          _v('1ㅇ', composing: const TextRange(start: 1, end: 2)), _v('1ㅇ'));
      expect(out.text, '1');
      expect(out.selection, const TextSelection.collapsed(offset: 1));
      expect(calls, [true]);
    });

    test('영문 조합(Android 자판 추천어 등)은 그대로', () {
      final out = f.formatEditUpdate(
          _v('ab'), _v('abc', composing: const TextRange(start: 0, end: 3)));
      expect(out.text, 'abc');
      expect(out.composing, const TextRange(start: 0, end: 3));
      expect(calls, [false]);
    });

    test('지우기는 안내 상태를 바꾸지 않는다', () {
      final out = f.formatEditUpdate(_v('abc'), _v('ab'));
      expect(out.text, 'ab');
      expect(calls, isEmpty);
    });

    test('이모지(서로게이트 쌍)는 통째로 버린다', () {
      final out = f.formatEditUpdate(_v('a'), _v('a😀b'));
      expect(out.text, 'ab');
      expect(out.selection, const TextSelection.collapsed(offset: 2));
    });
  });
}
