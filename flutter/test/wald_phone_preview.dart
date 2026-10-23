// Waldlust(DSK-12 — 부록 A-58): 폰 파일 전송 화면 미리보기. 연결 없이 가짜 목록·작업으로 모든 상태를 띄운다.
//
// flutter build apk --release --target-platform android-x64 -t test/wald_phone_preview.dart
//
// - 오른쪽 아래 단추로 하단 막대의 작업 상태를 차례로 바꾼다. 선택 막대는 목록 행을 길게 눌러 본다.
// - 세션이 없어 보내기·삭제·폴더 만들기·파일 열기는 실제로 동작하지 않는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/mobile/pages/file_manager_page.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

void main() async {
  isTest = true;
  waldMobileFileManagerPreview = true;
  WidgetsFlutterBinding.ensureInitialized();
  await initEnv(kAppTypeMain);
  runApp(GetMaterialApp(
    navigatorKey: globalKey,
    debugShowCheckedModeBanner: false,
    theme: MyTheme.lightTheme,
    themeMode: ThemeMode.light,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: supportedLocales,
    home: const _PhoneFileTransferPreview(),
  ));
}

class _PhoneFileTransferPreview extends StatefulWidget {
  const _PhoneFileTransferPreview();

  @override
  State<_PhoneFileTransferPreview> createState() =>
      _PhoneFileTransferPreviewState();
}

class _PhoneFileTransferPreviewState extends State<_PhoneFileTransferPreview> {
  static const _labels = [
    '작업 없음',
    '보내는 중 + 여러 건',
    '받는 중',
    '대기',
    '일시 정지',
    '받기 완료',
    '전송 실패',
    '삭제 완료',
    '취소됨',
  ];
  int _step = 0;
  String _received = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fill());
  }

  void _fill() {
    final model = gFFI.fileModel;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Entry entry(String name, int type, int size, int ago) => Entry()
      ..name = name
      ..entryType = type
      ..size = size
      ..modifiedTime = now - ago;

    final local = model.localController;
    local.options.value
      ..home = '/storage/emulated/0'
      ..isWindows = false;
    local.directory.value = FileDirectory()
      ..path = '/storage/emulated/0/Download'
      ..entries = [
        entry('매장 사진', 1, 0, 3600),
        entry('메뉴판_2026.pdf', 4, 2345678, 600),
        entry('영수증_1023.jpg', 4, 245760, 7200),
        entry('매장 영상.mp4', 4, 104857600, 259200),
        entry('sales_0930.csv', 4, 98765, 9000),
        entry('백업_1015.zip', 4, 52428800, 90000),
        entry('notes.txt', 4, 1234, 1200),
      ]
      ..format(false);

    final remote = model.remoteController;
    remote.options.value
      ..home = 'C:\\Users\\POS'
      ..isWindows = true;
    remote.directory.value = FileDirectory()
      ..path = 'C:\\Users\\POS\\Desktop'
      ..entries = [
        entry('C:', 3, 0, 0),
        entry('주문 백업', 1, 0, 1800),
        entry('Logs', 1, 0, 5400),
        entry('설정.ini', 4, 2048, 300),
        entry('sales_0930.csv', 4, 98765, 9000),
        entry('POS_Setup.msi', 4, 73400320, 500000),
        entry('error.log', 4, 40960, 100),
      ]
      ..format(true);

    // 받기 완료의 [파일 열기] 확인용 파일(앱 임시 폴더).
    final file = File('${Directory.systemTemp.path}/받은 메모.txt')
      ..writeAsStringSync('Waldlust 미리보기\n');
    _received = file.path;
  }

  // 작업 이름은 실제처럼 원본 전체 경로다(하단 막대에는 마지막 이름만 보여야 한다).
  JobProgress _job(int id, JobState state, String name,
          {JobType type = JobType.transfer,
          bool toLocal = false,
          int total = 98765000,
          int done = 45000000,
          String err = '',
          String to = ''}) =>
      JobProgress()
        ..id = id
        ..type = type
        ..state = state
        ..fileName = name
        ..jobName = name
        ..to = to
        ..totalSize = total
        ..finishedSize = done
        ..speed = state == JobState.inProgress ? 1536000 : 0
        ..isRemoteToLocal = toLocal
        ..err = err;

  void _next() {
    final table = gFFI.fileModel.jobController.jobTable;
    final step = (_step + 1) % _labels.length;
    const phone = '/storage/emulated/0/Download/';
    const pc = r'C:\Users\POS\Desktop\';
    final List<JobProgress> jobs = switch (step) {
      1 => [
          _job(1, JobState.inProgress, '$phone매장 영상.mp4'),
          _job(2, JobState.inProgress, '$phone메뉴판_2026.pdf', done: 0),
          _job(3, JobState.inProgress, '${phone}notes.txt', done: 0),
        ],
      2 => [_job(4, JobState.inProgress, '${pc}POS_Setup.msi', toLocal: true)],
      3 => [_job(5, JobState.none, '${phone}sales_0930.csv', done: 0)],
      4 => [
          _job(6, JobState.paused, '$pc주문 백업', toLocal: true,
              done: 10485760)
        ],
      5 => [
          _job(7, JobState.done, '$pc받은 메모.txt',
              toLocal: true, total: 4096, done: 4096, to: _received)
        ],
      6 => [
          _job(8, JobState.error, '$pc설정.ini',
              toLocal: true, total: 2048, done: 0, err: 'Permission denied')
        ],
      7 => [
          _job(9, JobState.done, '${phone}notes.txt',
              type: JobType.deleteFile, total: 0, done: 0)
        ],
      8 => [
          _job(10, JobState.done, '$phone백업_1015.zip', err: 'cancel')
        ],
      _ => [],
    };
    table
      ..clear()
      ..addAll(jobs);
    setState(() => _step = step);
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        FileManagerPage(id: 'wald-preview-ft'),
        Positioned(
          right: 12,
          bottom: 170,
          child: FilledButton.tonal(
            onPressed: _next,
            child: Text('상태: ${_labels[_step]} ▸'),
          ),
        ),
      ]);
}
