import 'dart:async';
import 'dart:io';

import 'package:extended_text/extended_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../../common.dart';
import '../../common/wald_local_open.dart';
import '../../common/widgets/dialog.dart';

// Waldlust(DSK-12): 디자인 미리보기(test/wald_phone_preview.dart)는 연결 없이 화면만 띄운다.
@visibleForTesting
bool waldMobileFileManagerPreview = false;

class FileManagerPage extends StatefulWidget {
  FileManagerPage(
      {Key? key,
      required this.id,
      this.password,
      this.isSharedPassword,
      this.forceRelay})
      : super(key: key);
  final String id;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;

  @override
  State<StatefulWidget> createState() => _FileManagerPageState();
}

enum SelectMode { local, remote, none }

extension SelectModeEq on SelectMode {
  bool eq(bool? currentIsLocal) {
    if (currentIsLocal == null) {
      return false;
    }
    if (currentIsLocal) {
      return this == SelectMode.local;
    } else {
      return this == SelectMode.remote;
    }
  }
}

extension SelectModeExt on Rx<SelectMode> {
  void toggle(bool currentIsLocal) {
    switch (value) {
      case SelectMode.local:
        value = SelectMode.none;
        break;
      case SelectMode.remote:
        value = SelectMode.none;
        break;
      case SelectMode.none:
        if (currentIsLocal) {
          value = SelectMode.local;
        } else {
          value = SelectMode.remote;
        }
        break;
    }
  }
}

class _FileManagerPageState extends State<FileManagerPage> {
  final model = gFFI.fileModel;
  final selectMode = SelectMode.none.obs;

  var showLocal = true;

  FileController get currentFileController =>
      showLocal ? model.localController : model.remoteController;
  FileDirectory get currentDir => currentFileController.directory.value;
  DirectoryOptions get currentOptions => currentFileController.options.value;
  final _uniqueKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    if (waldMobileFileManagerPreview) return;
    gFFI.start(widget.id,
        isFileTransfer: true,
        password: widget.password,
        isSharedPassword: widget.isSharedPassword,
        forceRelay: widget.forceRelay);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, widget.id);
    WakelockManager.enable(_uniqueKey);
  }

  @override
  void dispose() {
    if (!waldMobileFileManagerPreview) {
      model.close().whenComplete(() {
        gFFI.close();
        gFFI.dialogManager.dismissAll();
        WakelockManager.disable(_uniqueKey);
      });
    }
    model.jobController.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
      onWillPop: () async {
        if (selectMode.value != SelectMode.none) {
          selectMode.value = SelectMode.none;
          setState(() {});
        } else {
          currentFileController.goBack();
        }
        return false;
      },
      child: Scaffold(
        // Waldlust(DSK-12 — 부록 A-58): 회색 바탕 위 흰 목록 카드(데스크탑 파일 전송 창 톤).
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          leading: Row(children: [
            IconButton(
                icon: Icon(waldIcon(Icons.close)),
                onPressed: () => clientClose(gFFI.sessionId, gFFI)),
          ]),
          centerTitle: true,
          title: _waldSideTabs(),
          actions: [
            PopupMenuButton<String>(
                tooltip: "",
                icon: Icon(waldIcon(Icons.more_vert)),
                itemBuilder: (context) {
                  return [
                    PopupMenuItem(
                      child: Row(
                        children: [
                          Icon(waldIcon(Icons.refresh),
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Refresh"))
                        ],
                      ),
                      value: "refresh",
                    ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(waldIcon(Icons.check),
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Select"))
                        ],
                      ),
                      value: "select",
                    ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(waldIcon(Icons.folder_outlined),
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Create Folder"))
                        ],
                      ),
                      value: "folder",
                    ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(
                              currentOptions.showHidden
                                  ? waldIcon(Icons.check_box_outlined)
                                  : waldIcon(Icons.check_box_outline_blank),
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Show Hidden Files"))
                        ],
                      ),
                      value: "hidden",
                    )
                  ];
                },
                onSelected: (v) {
                  if (v == "refresh") {
                    currentFileController.refresh();
                  } else if (v == "select") {
                    model.localController.selectedItems.clear();
                    model.remoteController.selectedItems.clear();
                    selectMode.toggle(showLocal);
                    setState(() {});
                  } else if (v == "folder") {
                    final name = TextEditingController();
                    String? errorText;
                    gFFI.dialogManager.show((setState, close, context) {
                      name.addListener(() {
                        if (errorText != null) {
                          setState(() {
                            errorText = null;
                          });
                        }
                      });
                      return CustomAlertDialog(
                          title: Text(translate("Create Folder")),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                decoration: InputDecoration(
                                  labelText:
                                      translate("Please enter the folder name"),
                                  errorText: errorText,
                                ),
                                controller: name,
                              ).workaroundFreezeLinuxMint(),
                            ],
                          ),
                          actions: [
                            dialogButton("Cancel",
                                onPressed: () => close(false), isOutline: true),
                            dialogButton("OK", onPressed: () {
                              if (name.value.text.isNotEmpty) {
                                if (!PathUtil.validName(
                                    name.value.text,
                                    currentFileController
                                        .options.value.isWindows)) {
                                  setState(() {
                                    errorText =
                                        translate("Invalid folder name");
                                  });
                                  return;
                                }
                                currentFileController.createDir(PathUtil.join(
                                    currentDir.path,
                                    name.value.text,
                                    currentOptions.isWindows));
                                close();
                              }
                            })
                          ]);
                    });
                  } else if (v == "hidden") {
                    currentFileController.toggleShowHidden();
                  }
                }),
          ],
        ),
        body: showLocal
            ? FileManagerView(
                controller: model.localController,
                selectMode: selectMode,
              )
            : FileManagerView(
                controller: model.remoteController,
                selectMode: selectMode,
              ),
        bottomNavigationBar: bottomSheet(),
      ));

  // Waldlust(DSK-12 — 부록 A-58): 하늘색 로컬·원격 토글 대신 둘로 나뉜 탭(고른 쪽 검정 바탕·흰 글자 —
  // 브랜드 목록 선택과 같은 규칙).
  Widget _waldSideTabs() {
    Widget tab(bool local) {
      final selected = showLocal == local;
      final color = selected ? WaldPalette.white : WaldPalette.neutral700;
      return InkWell(
        borderRadius: BorderRadius.circular(WaldSize.radius - 2),
        onTap: selected ? null : _waldSwitchSide,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? WaldPalette.neutral900 : null,
            borderRadius: BorderRadius.circular(WaldSize.radius - 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(waldIcon(local ? Icons.phone_android_sharp : Icons.computer),
                size: WaldSize.iconSm, color: color),
            const SizedBox(width: 6),
            Text(translate(local ? 'My phone' : 'Remote device'),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: color)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WaldPalette.neutral100,
        borderRadius: BorderRadius.circular(WaldSize.radius),
      ),
      child: Row(
          mainAxisSize: MainAxisSize.min, children: [tab(true), tab(false)]),
    );
  }

  // 고른 채로 탭을 바꾸면 선택을 푼다 — 보내기는 선택 막대에서 바로 하므로 붙여넣기 단계가 없다.
  void _waldSwitchSide() {
    model.localController.selectedItems.clear();
    model.remoteController.selectedItems.clear();
    selectMode.value = SelectMode.none;
    setState(() => showLocal = !showLocal);
  }

  // Waldlust(DSK-12 — 부록 A-58): 반투명 하단 시트(목록을 가림) → 흰 하단 막대. 선택 중이면 고른 개수·받는 위치·
  // [삭제]·[보내기|받기](데스크탑처럼 반대편의 지금 폴더로 바로), 아니면 전송 작업 하나(진행 중인 것, 없으면 마지막).
  Widget? bottomSheet() {
    return Obx(() {
      final child = selectMode.value != SelectMode.none
          ? _waldSelectionBar()
          : _waldJobBar();
      if (child == null) return const SizedBox.shrink();
      return Container(
        decoration: const BoxDecoration(
          color: WaldPalette.white,
          border: Border(top: BorderSide(color: WaldPalette.neutral200)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: child,
          ),
        ),
      );
    });
  }

  Widget _waldSelectionBar() {
    final controller = currentFileController;
    final selected = controller.selectedItems;
    final count = selected.items.length;
    final entries = currentDir.entries.where((e) => !e.isDrive).toList();
    final allSelected = entries.isNotEmpty && count >= entries.length;
    final otherSide = showLocal ? model.remoteController : model.localController;
    const buttonSize = Size(0, 40);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(translate('{$count} selected'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WaldPalette.neutral900)),
          ),
          TextButton(
            onPressed: entries.isEmpty
                ? null
                : () {
                    if (allSelected) {
                      selected.clear();
                    } else {
                      selected.selectAll(entries);
                    }
                    setState(() {});
                  },
            child: Text(translate(allSelected ? 'Unselect All' : 'Select All')),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(waldIcon(Icons.close), size: WaldSize.iconLg),
            onPressed: () {
              selected.clear();
              selectMode.value = SelectMode.none;
              setState(() {});
            },
          ),
        ]),
        Row(children: [
          Text(
              '${translate('Destination')} · ${translate(showLocal ? 'Remote device' : 'My phone')}',
              style: const TextStyle(
                  fontSize: WaldSize.smallFont, color: WaldPalette.neutral500)),
          const SizedBox(width: 8),
          Expanded(
            child: ExtendedText(
              otherSide.directory.value.path,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: WaldSize.smallFont, color: WaldPalette.neutral700),
              overflowWidget: const TextOverflowWidget(
                  child: Text('…'), position: TextOverflowPosition.start),
            ),
          ),
        ]).marginOnly(bottom: 10),
        Row(children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: buttonSize),
            onPressed: count == 0
                ? null
                : () async {
                    await controller.removeAction(selected);
                    selected.clear();
                    selectMode.value = SelectMode.none;
                  },
            icon: Icon(waldIcon(Icons.delete_outline), size: WaldSize.icon),
            label: Text(translate('Delete')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(minimumSize: buttonSize),
              onPressed: SelectedItems.valid(selected.items)
                  ? () {
                      controller.sendFiles(
                          selected, controller.getOtherSideDirectoryData());
                      selected.clear();
                      selectMode.value = SelectMode.none;
                    }
                  : null,
              icon: Icon(waldIcon(showLocal ? Icons.upload : Icons.download),
                  size: WaldSize.icon),
              label: Text(translate(showLocal ? 'Send' : 'Receive')),
            ),
          ),
        ]),
      ],
    );
  }

  // 데스크탑 전송 목록과 같은 상태색: 오류 빨강·일시 정지 주황·완료 초록(취소·건너뜀은 회색), 그 밖은 아이콘 검정·글자 회색.
  Color _waldStateColor(JobProgress job, {bool text = false}) {
    switch (job.state) {
      case JobState.error:
        return WaldPalette.red600;
      case JobState.paused:
        return WaldPalette.amber600;
      case JobState.done:
        if (job.err == 'cancel' || job.err == 'skipped') {
          return WaldPalette.neutral500;
        }
        return text ? WaldPalette.green700 : WaldPalette.green600;
      default:
        return text ? WaldPalette.neutral500 : WaldPalette.neutral900;
    }
  }

  String _waldJobStatus(JobProgress job, bool isDelete) {
    switch (job.state) {
      case JobState.none:
        return translate(isDelete ? 'Deleting' : 'Waiting');
      case JobState.inProgress:
        if (isDelete) return translate('Deleting');
        final verb = translate(job.isRemoteToLocal ? 'Receiving' : 'Sending');
        return job.speed > 0
            ? '$verb · ${readableFileSize(job.speed)}/s'
            : verb;
      case JobState.paused:
        return translate('Paused');
      case JobState.done:
        if (job.err == 'cancel') return translate('Cancelled');
        if (job.err == 'skipped') return translate('Skipped');
        return translate(isDelete
            ? 'Deleted'
            : job.isRemoteToLocal
                ? 'Received'
                : 'Sent');
      case JobState.error:
        final failed = translate(isDelete ? 'Delete failed' : 'Transfer failed');
        return job.err.isEmpty ? failed : '$failed: ${translate(job.err)}';
    }
  }

  // 받기가 끝난 이 폰의 파일(실행 파일 아님)은 [파일 열기](DSK-08 모바일판 — Android 만).
  bool _waldCanOpenReceived(JobProgress job) =>
      isAndroid &&
      job.type == JobType.transfer &&
      job.isRemoteToLocal &&
      job.state == JobState.done &&
      job.err.isEmpty &&
      job.to.isNotEmpty &&
      FileSystemEntity.typeSync(job.to) == FileSystemEntityType.file &&
      !waldIsExecutable(job.to);

  Widget? _waldJobBar() {
    final jobTable = model.jobController.jobTable;
    if (jobTable.isEmpty) return null;
    // Rust 가 작업을 차례로 처리하므로 진행 중인 첫 작업이 실제로 보내는 작업이다.
    final job =
        jobTable.firstWhereOrNull((j) => j.state == JobState.inProgress) ??
            jobTable.last;
    final isDelete =
        job.type == JobType.deleteFile || job.type == JobType.deleteDir;
    final waiting = jobTable
        .where((j) =>
            !identical(j, job) &&
            (j.state == JobState.none ||
                j.state == JobState.inProgress ||
                j.state == JobState.paused))
        .length;
    var status = _waldJobStatus(job, isDelete);
    if (waiting > 0) status += ' · ${translate('{$waiting} more')}';
    final parts = job.jobName.split(RegExp(r'[\\/]'))
      ..removeWhere((e) => e.isEmpty);
    final name = parts.isEmpty ? job.jobName : parts.last;
    final running = job.state == JobState.none ||
        job.state == JobState.inProgress ||
        job.state == JobState.paused;

    Widget button(String label, VoidCallback onPressed, {bool primary = false}) {
      final style = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12)),
      );
      final text = Text(translate(label));
      return (primary
              ? ElevatedButton(style: style, onPressed: onPressed, child: text)
              : OutlinedButton(style: style, onPressed: onPressed, child: text))
          .marginOnly(left: 6);
    }

    return Row(children: [
      Icon(
          waldIcon(isDelete
              ? Icons.delete_outline
              : job.isRemoteToLocal
                  ? Icons.download
                  : Icons.upload),
          size: 22,
          color: _waldStateColor(job)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExtendedText(
              name,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: WaldPalette.neutral900),
              overflowWidget: const TextOverflowWidget(
                  child: Text('…'), position: TextOverflowPosition.start),
            ),
            Text(status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: WaldSize.smallFont,
                  color: _waldStateColor(job, text: true),
                  fontFeatures: const [FontFeature.tabularFigures()],
                )).marginOnly(top: 2),
            if (job.type == JobType.transfer &&
                job.state == JobState.inProgress)
              LinearPercentIndicator(
                animateFromLastPercent: true,
                padding: EdgeInsets.zero,
                lineHeight: 4,
                barRadius: const Radius.circular(2),
                percent: job.percent.clamp(0.0, 1.0),
                progressColor: MyTheme.accent,
                backgroundColor: WaldPalette.neutral100,
                trailing: SizedBox(
                  width: 40,
                  child: Text(job.percentText,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: WaldSize.smallFont,
                        color: WaldPalette.neutral600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      )),
                ),
              ).marginOnly(top: 6),
          ],
        ),
      ),
      if (job.state == JobState.paused)
        button('Resume', () => model.jobController.resumeJob(job.id),
            primary: true),
      if (running)
        button('Cancel', () {
          model.jobController.cancelJob(job.id);
          jobTable.clear();
        }),
      if (!running && _waldCanOpenReceived(job))
        button('Open file', () => waldOpenLocalFile(job.to), primary: true),
      if (!running) button('Close', () => jobTable.clear()),
    ]);
  }

  SelectedItems? getActiveSelectedItems() {
    final localSelectedItems = model.localController.selectedItems;
    final remoteSelectedItems = model.remoteController.selectedItems;

    if (localSelectedItems.items.isNotEmpty &&
        remoteSelectedItems.items.isNotEmpty) {
      // assert unreachable
      debugPrint("Wrong SelectedItems state, reset");
      localSelectedItems.clear();
      remoteSelectedItems.clear();
    }

    if (localSelectedItems.items.isEmpty && remoteSelectedItems.items.isEmpty) {
      return null;
    }

    if (localSelectedItems.items.length > remoteSelectedItems.items.length) {
      return localSelectedItems;
    } else {
      return remoteSelectedItems;
    }
  }
}

class FileManagerView extends StatefulWidget {
  final FileController controller;
  final Rx<SelectMode> selectMode;

  FileManagerView({required this.controller, required this.selectMode});

  @override
  State<StatefulWidget> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  final _listScrollController = ScrollController();
  final _breadCrumbScroller = ScrollController();
  late final ascending = Rx<bool>(controller.sortAscending);

  bool get isLocal => widget.controller.isLocal;
  FileController get controller => widget.controller;
  SelectedItems get _selectedItems => widget.controller.selectedItems;

  @override
  void initState() {
    super.initState();
    controller.directory.listen((e) => breadCrumbScrollToEnd());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      headTools(),
      Expanded(child: Obx(() {
        final entries = controller.directory.value.entries;
        // Waldlust(DSK-12 — 부록 A-58): 데스크탑 파일 전송 창처럼 흰 카드 하나 안의 표 행(행마다 카드를 띄우지 않는다).
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          clipBehavior: Clip.antiAlias,
          decoration: waldCardDecoration(),
          // 행(ListTile)의 선택 바탕·누름 효과는 가까운 Material 에 그려진다 — 카드의 흰 바탕 위에 투명 Material 을 둔다.
          child: Material(
            type: MaterialType.transparency,
            child: ListView.separated(
              controller: _listScrollController,
              itemCount: entries.length + 1,
              separatorBuilder: (context, index) => const Divider(
                  height: 1, thickness: 1, color: WaldPalette.neutral100),
              itemBuilder: (context, index) {
                if (index >= entries.length) {
                  return listTail();
                }
                final entry = entries[index];
                var selected = false;
                if (widget.selectMode.value != SelectMode.none) {
                  selected = _selectedItems.items.contains(entry);
                }

                final sizeStr =
                    entry.isFile ? readableFileSize(entry.size.toDouble()) : "";

                final showCheckBox = () {
                  return widget.selectMode.value != SelectMode.none &&
                      widget.selectMode.value.eq(controller.selectedItems.isLocal);
                }();
                return ListTile(
                  selected: selected,
                  selectedTileColor: WaldPalette.neutral200,
                  selectedColor: WaldPalette.neutral900,
                  leading: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (showCheckBox && !entry.isDrive)
                      Checkbox(
                          visualDensity: VisualDensity.compact,
                          value: selected,
                          onChanged: (v) {
                            if (v == null) return;
                            if (v && !selected) {
                              _selectedItems.add(entry);
                            } else if (!v && selected) {
                              _selectedItems.remove(entry);
                            }
                            setState(() {});
                          }),
                    // 종류 아이콘 — 폴더만 주황, 드라이브 n600, 파일 n500(데스크탑과 같다).
                    waldIconBox(
                        waldFileEntryIcon(entry.name,
                            isDir: !entry.isFile, isDrive: entry.isDrive),
                        color: entry.isDrive
                            ? WaldPalette.neutral600
                            : entry.isFile
                                ? WaldPalette.neutral500
                                : WaldPalette.amber500),
                  ]),
                  title: Text(entry.name, style: const TextStyle(fontSize: 14)),
                  subtitle: entry.isDrive
                      ? null
                      : Text(
                          [
                            entry.lastModified().toString().replaceAll(".000", ""),
                            if (sizeStr.isNotEmpty) sizeStr
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: WaldSize.smallFont,
                              color: WaldPalette.neutral500,
                              fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                  trailing: entry.isDrive || showCheckBox
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: "",
                          icon: Icon(waldIcon(Icons.more_vert)),
                          itemBuilder: (context) {
                            return [
                              if (versionCmp(gFFI.ffiModel.pi.version, "1.3.0") >=
                                  0)
                                PopupMenuItem(
                                  child: Text(translate("Rename")),
                                  value: "rename",
                                ),
                              PopupMenuItem(
                                child: Text(translate("Delete")),
                                value: "delete",
                              ),
                              PopupMenuItem(
                                child: Text(translate("Select")),
                                value: "multi_select",
                              ),
                            ];
                          },
                          onSelected: (v) {
                            if (v == "delete") {
                              final items = SelectedItems(isLocal: isLocal);
                              items.add(entry);
                              controller.removeAction(items);
                            } else if (v == "multi_select") {
                              _selectedItems.clear();
                              widget.selectMode.toggle(isLocal);
                              if (widget.selectMode.value != SelectMode.none) {
                                _selectedItems.add(entry);
                              }
                              setState(() {});
                            } else if (v == "rename") {
                              controller.renameAction(entry, isLocal);
                            }
                          }),
                  onTap: () {
                    if (showCheckBox) {
                      if (selected) {
                        _selectedItems.remove(entry);
                      } else {
                        _selectedItems.add(entry);
                      }
                      setState(() {});
                      return;
                    }
                    if (entry.isDirectory || entry.isDrive) {
                      controller.openDirectory(entry.path);
                    } else if (isLocal && isAndroid) {
                      // Waldlust(DSK-12 — DSK-08 모바일판): 이 폰의 파일을 누르면 기본 앱으로 연다.
                      waldOpenLocalFile(entry.path);
                    } else {
                      // Perform file-related tasks.
                    }
                  },
                  onLongPress: entry.isDrive
                      ? null
                      : () {
                          _selectedItems.clear();
                          widget.selectMode.toggle(isLocal);
                          if (widget.selectMode.value != SelectMode.none) {
                            _selectedItems.add(entry);
                          }
                          setState(() {});
                        },
                );
              },
            ),
          ),
        );
      }))
    ]);
  }

  void breadCrumbScrollToEnd() {
    Future.delayed(Duration(milliseconds: 200), () {
      if (_breadCrumbScroller.hasClients) {
        _breadCrumbScroller.animateTo(
            _breadCrumbScroller.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.fastLinearToSlowEaseIn);
      }
    });
  }

  Widget headTools() => Container(
          child: Row(
        children: [
          Expanded(child: Obx(() {
            final home = controller.options.value.home;
            final isWindows = controller.options.value.isWindows;
            return BreadCrumb(
              items: getPathBreadCrumbItems(controller.shortPath, isWindows,
                  () => controller.goToHomeDirectory(), (list) {
                var path = "";
                if (home.startsWith(list[0])) {
                  // absolute path
                  for (var item in list) {
                    path = PathUtil.join(path, item, isWindows);
                  }
                } else {
                  path += home;
                  for (var item in list) {
                    path = PathUtil.join(path, item, isWindows);
                  }
                }
                controller.openDirectory(path);
              }),
              divider: Icon(waldIcon(Icons.chevron_right),
                  size: 14, color: WaldPalette.neutral400),
              overflow: ScrollableOverflow(controller: _breadCrumbScroller),
            );
          })),
          Row(
            children: [
              IconButton(
                icon: Icon(waldIcon(Icons.arrow_back)),
                onPressed: controller.goBack,
              ),
              IconButton(
                icon: Icon(waldIcon(Icons.arrow_upward)),
                onPressed: controller.goToParentDirectory,
              ),
              PopupMenuButton<SortBy>(
                  tooltip: "",
                  icon: Icon(waldIcon(Icons.sort)),
                  itemBuilder: (context) {
                    return SortBy.values
                        .map((e) => PopupMenuItem(
                              child: Text(translate(e.toString())),
                              value: e,
                            ))
                        .toList();
                  },
                  onSelected: (sortBy) {
                    // If selecting the same sort option, flip the order
                    // If selecting a different sort option, use ascending order
                    if (controller.sortBy.value == sortBy) {
                      ascending.value = !controller.sortAscending;
                    } else {
                      ascending.value = true;
                    }
                    controller.changeSortStyle(sortBy,
                        ascending: ascending.value);
                  }),
            ],
          )
        ],
      ));

  // Waldlust(DSK-12 — 부록 A-58): 끝 줄은 '전체 N 항목'만(경로는 위 경로 줄에 있고, 하단 막대가 목록을 가리지 않는다).
  Widget listTail() => Obx(() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          "${translate("Total")} ${controller.directory.value.entries.length} ${translate("items")}",
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: WaldSize.smallFont, color: WaldPalette.neutral500),
        ),
      ));

  List<BreadCrumbItem> getPathBreadCrumbItems(String shortPath, bool isWindows,
      void Function() onHome, void Function(List<String>) onPressed) {
    final list = PathUtil.split(shortPath, isWindows);
    final breadCrumbList = [
      BreadCrumbItem(
          content: IconButton(
        icon: Icon(waldIcon(Icons.home_filled),
            size: WaldSize.iconLg, color: WaldPalette.neutral600),
        onPressed: onHome,
      ))
    ];
    // Waldlust(DSK-12 — 부록 A-58): 앞 조각은 회색, 지금 폴더는 굵은 검정.
    breadCrumbList.addAll(list.asMap().entries.map((e) => BreadCrumbItem(
        content: TextButton(
            child: Text(e.value,
                style: e.key == list.length - 1
                    ? const TextStyle(
                        color: WaldPalette.neutral900,
                        fontWeight: FontWeight.w600)
                    : const TextStyle(color: WaldPalette.neutral500)),
            style:
                ButtonStyle(minimumSize: MaterialStateProperty.all(Size(0, 0))),
            onPressed: () => onPressed(list.sublist(0, e.key + 1))))));
    return breadCrumbList;
  }
}

class BottomSheetBody extends StatelessWidget {
  BottomSheetBody(
      {required this.leading,
      required this.title,
      required this.text,
      this.onCanceled,
      this.actions});

  final Widget leading;
  final String title;
  final String text;
  final VoidCallback? onCanceled;
  final List<IconButton>? actions;

  @override
  BottomSheet build(BuildContext context) {
    // ignore: no_leading_underscores_for_local_identifiers
    final _actions = actions ?? [];
    return BottomSheet(
      builder: (BuildContext context) {
        return Container(
            height: 65,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: MyTheme.accent50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      leading,
                      SizedBox(width: 16),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 18)),
                          Text(text,
                              style: TextStyle(fontSize: 14)) // TODO color
                        ],
                      )
                    ],
                  ),
                  Row(children: () {
                    _actions.add(IconButton(
                      icon: Icon(waldIcon(Icons.cancel_outlined)),
                      onPressed: onCanceled,
                    ));
                    return _actions;
                  }())
                ],
              ),
            ));
      },
      onClosing: () {},
      // backgroundColor: MyTheme.grayBg,
      enableDrag: false,
    );
  }
}
