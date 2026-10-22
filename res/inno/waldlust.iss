; Waldlust 원격지원 — 표준 Windows 설치 프로그램(Inno Setup).
;
; 설계 의도(중요):
;  - 자기추출 packer/requireAdministrator/자동 silent-install 을 버리고, "흔한 Inno 인스톨러"
;    한 개로 배포한다. Defender ML 이 가장 덜 의심하는 형태.
;  - 이 인스톨러는 파일 복사 + 제어판 등록 + 시작메뉴만 담당한다. 덮어 설치 때는 복사 전에 실행 중인 앱을 끈다([Code], 부록 A-40).
;  - 서비스 등록/방화벽/URL 프로토콜 같은 RustDesk 고유 작업은 앱 본체의
;    "Waldlust.exe --after-install" 을 호출해서 위임한다(설치 시 메인 exe 를 Waldlust.exe 로 넣음).
;  - 설치 경로는 반드시 {autopf}\Waldlust Remote 로 고정한다. RustDesk 의 --after-install /
;    --uninstall 이 get_default_install_path()=="C:\Program Files\Waldlust Remote"(src/platform/windows.rs
;    WALD_INSTALL_DIR_NAME) 를 기준으로 exe 를 찾기 때문. (경로를 바꾸면 서비스 등록이 어긋난다 → DisableDirPage=yes,
;    UsePreviousAppDir=no) APP_NAME(Waldlust) 폴더를 쓰지 않는 것은 회사 POS 가 Program Files (x86)\Waldlust 를
;    쓰기 때문이다(DSK-01, 부록 A-21).
;
; 빌드: ISCC.exe /DMyBuildDir=<flutter build 산출물 폴더> waldlust.iss
; 수신 전용 빌드(DSK-01)는 /DMyVariantSuffix=-incoming 을 더해 산출물 이름만 바꾼다.
; 산출물 이름(결정 D36): waldlust-remote[-incoming]-<버전>-windows-<x64|x86>.exe — macOS·Android 설치 파일과 같은 규칙.
; 32비트 Windows(Sciter, DSK-07 부록 A-19)는 /DMyArch=x86 — MyBuildDir 에 wald-remote.exe(Sciter) + sciter.dll 을 둔다.
;  32비트 설치라 64비트 Windows 에서는 {autopf} = Program Files (x86) 이고, 32비트 앱의 get_default_install_path() 도 같은 곳이다.
; AppId·설치 경로·서비스 이름은 두 변형이 같아서, 한쪽 설치 위에 다른 쪽을 덮어 설치하면 ID 가 유지된다.

#ifndef MyAppVersion
  #define MyAppVersion "1.5.6"
#endif
#ifndef MyBuildDir
  #define MyBuildDir "rustdesk"
#endif
#ifndef MyVariantSuffix
  #define MyVariantSuffix ""
#endif
#ifndef MyArch
  #define MyArch "x64"
#endif

[Setup]
AppId={{C5B0E6A2-4B3D-4F1E-9A7C-WALDLUST0001}
AppName=Waldlust 원격지원
AppVersion={#MyAppVersion}
AppPublisher=Waldlust Co., Ltd.
AppPublisherURL=https://remote.waldpay.co.kr
DefaultDirName={autopf}\Waldlust Remote
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
DefaultGroupName=Waldlust 원격지원
UninstallDisplayName=Waldlust 원격지원
UninstallDisplayIcon={app}\Waldlust.exe
#if MyArch == "x86"
OutputBaseFilename=waldlust-remote{#MyVariantSuffix}-{#MyAppVersion}-windows-x86
#else
OutputBaseFilename=waldlust-remote{#MyVariantSuffix}-{#MyAppVersion}-windows-x64
#endif
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
#if MyArch != "x86"
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
SetupIconFile=..\icon.ico
CloseApplications=yes
; 설치가 끝나면 탐색기에 아이콘 갱신을 알린다(SHChangeNotify SHCNE_ASSOCCHANGED). 같은 경로의 exe 를 덮어쓰면
; 탐색기가 바탕화면·시작 메뉴 바로가기에 옛 아이콘을 계속 보여 주기 때문이다(DSK-10).
ChangesAssociations=yes
; 오픈소스 고지(D35 — 명세 부록 A-25): 설치 첫 화면에 안내(GPL 은 동의를 요구하지 않으므로 LicenseFile 대신
; InfoBeforeFile). 라이선스·수정 고지·제3자 고지 파일(LICENCE.txt·NOTICE.txt·THIRD_PARTY_NOTICES.txt)은 빌드 스크립트가
; MyBuildDir 에 넣어 두고 아래 [Files] 의 폴더 복사로 함께 설치된다.
AppCopyright=Copyright © 2025 Purslane Ltd. Modifications © 2026 Waldlust Co., Ltd. (AGPL-3.0)
InfoBeforeFile=notice-ko.txt
; 코드서명은 SignTool 을 등록해 두면 여기서 자동 적용된다(향후):
; SignTool=mysigner
; SignedUninstaller=yes

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
; flutter windows 빌드 산출물 폴더 전체(DLL + data\ 등)를 복사하되, 메인 exe(wald-remote.exe)는 제외.
; 메인 exe 는 아래에서 반드시 "Waldlust.exe" 로 이름을 바꿔 설치한다.
;  이유(핵심 버그 수정): 앱 내부(APP_NAME=Waldlust)는 --after-install 시 서비스 바이너리를
;  get_default_install_path()\Waldlust.exe 로 등록한다. 그런데 빌드 산출물의 exe 이름은
;  wald-remote.exe 라서, 그대로 깔면 서비스가 없는 Waldlust.exe 를 가리켜 시작 실패(에러 2)한다.
;  → 파일명을 Waldlust.exe 로 맞춰야 서비스가 정상 기동한다.
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Excludes: "wald-remote.exe"; \
  Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#MyBuildDir}\wald-remote.exe"; DestDir: "{app}"; DestName: "Waldlust.exe"; \
  Flags: ignoreversion

[Icons]
Name: "{group}\Waldlust 원격지원"; Filename: "{app}\Waldlust.exe"
Name: "{group}\Waldlust 원격지원 제거"; Filename: "{uninstallexe}"
; 바탕화면 숏컷(모든 사용자 공용 데스크톱). 관리자 설치라 {autodesktop}={commondesktop}.
Name: "{autodesktop}\Waldlust 원격지원"; Filename: "{app}\Waldlust.exe"; \
  IconFilename: "{app}\Waldlust.exe"; Comment: "Waldlust 원격지원"

[Run]
; RustDesk 고유 설치 후처리: 서비스(sc create) + 방화벽 예외 + rustdesk:// 프로토콜 등록.
; 파일이 이미 {app} 에 복사된 상태에서 호출해야 하며, 관리자 권한으로 실행된다(인스톨러가 admin).
Filename: "{app}\Waldlust.exe"; Parameters: "--after-install"; \
  StatusMsg: "서비스 등록 중..."; Flags: runhidden waituntilterminated
; 이중 보장(belt-and-suspenders): --after-install 의 서비스 시작이 타이밍/권한 문제로 실패해도
; 무인 원격이 끊기지 않도록 서비스 자동시작·즉시시작·크래시 자동복구를 인스톨러에서 한 번 더 확정한다.
; (이미 되어 있으면 무해 — sc start 는 이미 실행 중이면 1056 을 반환하고 끝. 서비스 미생성 시엔
;  config/start 가 1060 으로 실패하지만 위 --after-install 이 생성을 책임진다.)
Filename: "{sys}\sc.exe"; Parameters: "config Waldlust start= auto"; \
  StatusMsg: "서비스 자동시작 설정..."; Flags: runhidden waituntilterminated
Filename: "{sys}\sc.exe"; Parameters: "failure Waldlust reset= 86400 actions= restart/5000/restart/5000/restart/10000"; \
  Flags: runhidden waituntilterminated
Filename: "{sys}\sc.exe"; Parameters: "start Waldlust"; \
  StatusMsg: "서비스 시작 중..."; Flags: runhidden waituntilterminated
; Waldlust(부록 A-40): 덮어 설치로 끈 트레이를 로그인 사용자 권한으로 다시 띄운다(이미 떠 있으면 --tray 가 스스로 끝난다).
Filename: "{app}\Waldlust.exe"; Parameters: "--tray"; Flags: nowait runasoriginaluser skipifsilent
; Waldlust(부록 A-40): 설치 완료 화면의 '실행' 체크박스(기본 켬). postinstall 은 로그인 사용자 권한으로 실행된다(관리자 창 방지).
Filename: "{app}\Waldlust.exe"; Description: "{cm:LaunchProgram,Waldlust 원격지원}"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
; 제거 시: 서비스 중지·삭제 + 방화벽 규칙 삭제 + 레지스트리 정리.
Filename: "{app}\Waldlust.exe"; Parameters: "--before-uninstall"; \
  Flags: runhidden waituntilterminated; RunOnceId: "WaldlustBeforeUninstall"

[Code]
// Waldlust(부록 A-40): 덮어 설치(업데이트) 때 실행 중인 서비스·서버·트레이·메인 창·CM 을 파일 복사 전에 끈다.
//  - 서비스를 먼저 멈춘다. 서비스는 --server 를 다시 띄우고, 서비스 프로세스가 죽으면 sc failure 복구가 5초 뒤
//    옛 exe 를 다시 띄운다 → 복구 동작을 잠시 끄고([Run] 이 다시 넣는다) net stop 으로 멈출 때까지 기다린 뒤 남은 프로세스를 끝낸다.
//  - 새 설치(서비스 없음)면 sc query 가 1060 이라 서비스는 건드리지 않는다. taskkill 결과는 보지 않는다.
//  - 파일 설치 전에 취소·실패하면 DeinitializeSetup 이 복구 동작과 서비스를 되살린다.
var
  WaldServiceStopped: Boolean;
  WaldInstalled: Boolean;

procedure WaldExec(const FileName, Params: String);
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant(FileName), Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  if Exec(ExpandConstant('{sys}\sc.exe'), 'query Waldlust', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
    and (ResultCode = 0) then
  begin
    WaldServiceStopped := True;
    WaldExec('{sys}\sc.exe', 'failure Waldlust reset= 0 actions= ""');
    WaldExec('{sys}\net.exe', 'stop Waldlust');
  end;
  WaldExec('{sys}\taskkill.exe', '/F /IM Waldlust.exe');
  WaldExec('{sys}\taskkill.exe', '/F /IM RuntimeBroker_rustdesk.exe');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    WaldInstalled := True;
end;

procedure DeinitializeSetup();
begin
  if WaldServiceStopped and not WaldInstalled then
  begin
    WaldExec('{sys}\sc.exe', 'failure Waldlust reset= 86400 actions= restart/5000/restart/5000/restart/10000');
    WaldExec('{sys}\sc.exe', 'start Waldlust');
  end;
end;
