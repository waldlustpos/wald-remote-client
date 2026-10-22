// Waldlust(DSK-08): 받은 파일을 OS 기본 앱으로 열거나, 받은 위치를 열어 그 항목을 선택한다.
//
// - 실행 파일은 열지 않고 폴더에서 보기만 한다(명세 Q-16 (c), 2026-10-02 사용자 결정).
// - '폴더 열기'는 늘 상위 폴더를 열고 그 항목을 선택한다. 폴더·macOS 앱 번들(.app)을 실행하지 않는다.
// - Windows 는 explorer.exe 에 경로를 프로세스 인자로 넘긴다(한글·공백 경로). explorer 는 쉼표를
//   인자 구분으로 읽어 쉼표가 든 경로는 url_launcher 로 연다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

const Set<String> _kWaldExecutableExts = {
  '.exe',
  '.msi',
  '.bat',
  '.cmd',
  '.com',
  '.ps1',
  '.vbs',
  '.vbe',
  '.js',
  '.jse',
  '.wsf',
  '.scr',
  '.pif',
  '.lnk',
  '.reg',
  '.hta',
  '.jar',
  '.apk',
  '.sh',
  '.command',
  '.app',
  '.pkg'
};

/// 확장자로 본 실행 파일 여부.
bool waldIsExecutable(String path) =>
    _kWaldExecutableExts.contains(p.extension(path).toLowerCase());

/// [path] 를 OS 기본 앱으로 연다. 실행 파일이면 폴더에서 보기로 대신한다.
Future<void> waldOpenLocalFile(String path) =>
    _waldOpenLocal(path, reveal: waldIsExecutable(path));

/// [path] 가 있는 폴더를 열고 그 항목을 선택한다.
Future<void> waldRevealLocalPath(String path) =>
    _waldOpenLocal(path, reveal: true);

Future<void> _waldOpenLocal(String path, {required bool reveal}) async {
  if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
    showToast(translate('File not found'));
    return;
  }
  try {
    if (Platform.isAndroid) {
      // Waldlust(DSK-12): Android 는 '폴더에서 보기'가 없어 실행 파일(Q-16 (c))은 위치만 알린다.
      // 그 밖의 파일은 FileProvider 로 기본 앱에 넘긴다(MainActivity 'wald_open_file' → WaldFiles.kt).
      if (reveal) {
        showToast(p.dirname(path));
        return;
      }
      final r = await platformFFI.invokeMethod('wald_open_file', path);
      if (r != 'ok') throw '$r';
    } else if (Platform.isMacOS) {
      final r = await Process.run('open', reveal ? ['-R', path] : [path]);
      if (r.exitCode != 0) throw '${r.exitCode} ${r.stderr}';
    } else if (Platform.isWindows && !path.contains(',')) {
      // explorer 는 성공해도 종료 코드 1 을 돌려줄 때가 있어 결과를 보지 않는다.
      await Process.run('explorer.exe', reveal ? ['/select,', path] : [path]);
    } else {
      final target = reveal ? p.dirname(path) : path;
      if (!await launchUrl(Uri.file(target))) throw 'launchUrl false';
    }
  } catch (e) {
    debugPrint('waldOpenLocal($path, reveal: $reveal): $e');
    showToast(translate('Failed to open'));
  }
}
