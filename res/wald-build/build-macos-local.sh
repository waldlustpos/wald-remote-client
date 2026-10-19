#!/bin/zsh
# Waldlust(wald-remote-client) macOS .app 로컬 빌드 — Apple Silicon(arm64) 호스트.
# 2026-09-29 에 재현한 절차를 한 파일로 모은 것이다. CI 원본: .github/workflows/wald-macos.yml, .github/workflows/bridge.yml
#
# 사용:  zsh ~/wald-build/build-macos-local.sh [커밋·브랜치] [bidirectional|incoming] [dummy|mock|prodtest|release]   (기본 waldlust, bidirectional, dummy)
#        인자 순서는 build-android-local.sh 와 같다. 슬래시 명령 /build-macos-bidirectional 이 이 스크립트를 부른다.
# 결과:  ~/wald-build/waldlust-<버전>-macos-localtest[-incoming].app (prodtest 는 -macos-prodtest, ad-hoc 서명), 로그는 ~/wald-build/logs/macos-*.log
#        + ~/wald-build/dist/<버전>-<sha9>-<대상>/waldlust-remote[-incoming]-<버전>-macos-arm64[-<대상>].dmg 와 manifest-macos-<변형>.txt
#        (설치 파일 이름 규칙 — 결정 D36: release 는 '-<대상>' 을 붙이지 않는다. 예 waldlust-remote-1.5.0-macos-arm64.dmg)
#
# 원칙
# - 비관리 빌드: WALDLUST_PRESET_PASSWORD 를 넣지 않는다.
# - 수신 전용(incoming)은 아직 막아 둔다(DSK-01 macOS 후속). 열 때는 build-android-local.sh 의 'variant incoming' 블록
#   (테스트 비밀번호 해시·지문)을 옮겨 오고 아래 case 의 incoming 줄을 SUFFIX="-incoming" 으로 바꾼다. 이름·manifest 는 이미 변형을 따른다.
# - 운영 어드민에 보고하지 않는다: WALDLUST_HEARTBEAT_URL 을 컴파일 때 넣는다(option_env!, 빌드 시점에 박힌다).
#   dummy: http://127.0.0.1:9/api/heartbeat(받는 곳 없음). WALDLUST_API_SERVER 는 호출자가 준 값을 그대로 쓴다.
#   mock:  http://127.0.0.1:8787/api/heartbeat + WALDLUST_API_SERVER=http://127.0.0.1:8787/rd
#          (wald-remote-docs/tools/rd-mock — 앱을 띄우기 전에 먼저 띄운다). build-windows-local.ps1 -Target 과 같다.
#   prodtest: 운영 서버로 보내는 시험 빌드(계획 ADMIN_LOCAL_PLAN C4, 결정 D16 — 2026-10-14 사용자). heartbeat = https://remote.waldpay.co.kr/api/heartbeat,
#          WALDLUST_API_SERVER = https://remote.waldpay.co.kr/rd. 비관리·ad-hoc 서명 그대로이고 현장 배포용이 아니다(저장소 이전 전 — REPO_TRANSITION).
#          시험 기기는 운영 목록에 '미지정'으로 올라간다. 결과 이름이 localtest 가 아니라 prodtest 라 dummy·mock 시험본을 덮지 않는다.
#   release: 정식 배포본(계획 ADMIN_LOCAL_PLAN 4-1, 결정 D33~D35 — 2026-10-14 사용자). 주소는 prodtest 와 같다.
#          ref 는 waldlustpos(origin)에 푸시된 wald-v* 태그만 받는다(재현성 — 소스 링크가 이 태그를 가리킨다).
#          태그 wald-v<버전>-r<N> 의 버전이 소스(pubspec·Cargo.toml) 버전과 달라도 멈춘다(D36).
#          서명 전에 NOTICE·LICENCE·THIRD_PARTY_NOTICES-macos.txt(res/wald-build/collect-notices.py)를 앱 Resources 에 넣고
#          dist 에도 둔다. 번들 ID co.kr.waldlust.remote·URL 스킴 waldlust 를 확인한다.
#          서명은 Developer ID + 공증(2026-10-16 사용자 — 명세 Q-42, D34 의 ad-hoc 을 바꿈): 번들 안쪽 코드부터 하드닝 런타임·타임스탬프로
#          서명하고(실행 파일에는 Release.entitlements), 앱과 dmg 를 각각 공증·스테이플한다. 서명 주체 WALD_MAC_SIGN_ID(기본 회사
#          Developer ID Application), 공증 keychain 프로필 WALD_NOTARY_PROFILE(기본 wald-notary). 시험본(dummy·mock·prodtest)은 ad-hoc 그대로.
#          cargo-about 0.6.4(cargo install cargo-about --version 0.6.4 --locked)가 있어야 한다.
# - 공용 작업 폴더는 건드리지 않는다. 별도 git worktree 에서 빌드하고 cargo target(~/wald-build/target-macos)을 분리한다.
#   vcpkg 루트는 ~/vcpkg(arm64-osx 전용)다. Android 빌드는 ~/vcpkg-android 를 쓴다(같은 루트에 다른 트리플렛을 설치하면 기존 설치분이 purge 된다).
#
# 전제(한 번 설치해 둔 것):
#   Xcode(2026-09-29 기준 27.0, xcode-select 로 선택·라이선스 동의), brew: llvm create-dmg cocoapods cmake nasm pkgconf,
#   rustup + 1.75(브리지) + 1.81(본 빌드, 타깃 aarch64-apple-darwin), cargo-expand 1.0.95, flutter_rust_bridge_codegen 1.80.1,
#   ~/fvm/versions/3.24.5(.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff 적용 + binding.dart 의 _setFramesEnabledState(false) 주석 처리),
#   ~/vcpkg(120deac3062162151622ca4860575a33844ba10b, bootstrap 완료)
set -u
R=/Users/kimsungchun/Documents/GitHub/wald-remote-client
OUT="$HOME/wald-build"
W="$OUT/wt-macos"
LOG="$OUT/logs"; mkdir -p "$LOG"
BASE="${1:-waldlust}"
VARIANT="${2:-bidirectional}"
case "$VARIANT" in
  bidirectional) SUFFIX="" ;;
  incoming) echo "FAIL: macOS 수신 전용은 아직 지원하지 않는다(DSK-01 macOS 후속 — 머리 주석 참고)"; exit 1 ;;
  *) echo "FAIL: 변형은 bidirectional 또는 incoming(둘째 인자, 대상은 셋째 인자)"; exit 1 ;;
esac
TARGET="${3:-dummy}"
case "$TARGET" in dummy|mock|prodtest|release) ;; *) echo "FAIL: 대상은 dummy·mock·prodtest·release"; exit 1 ;; esac
KIND=localtest; [ "$TARGET" = prodtest ] && KIND=prodtest; [ "$TARGET" = release ] && KIND=release
PROD=""; { [ "$TARGET" = prodtest ] || [ "$TARGET" = release ]; } && PROD=1   # 운영 주소로 빌드한다
TSUF="-$TARGET"; [ "$TARGET" = release ] && TSUF=""   # dist 설치 파일 이름 끝(D36 — 정식본은 대상 이름 없음)
FLUTTER_BIN="$HOME/fvm/versions/3.24.5/bin"
MIN_MACOS_VERSION=12.3
SIGN_ID="${WALD_MAC_SIGN_ID:-Developer ID Application: Waldlust Co., Ltd. (GFY79GHBW8)}"   # release 만
NOTARY_PROFILE="${WALD_NOTARY_PROFILE:-wald-notary}"
SIG_NOTE="ad-hoc (not notarized)"; [ "$TARGET" = release ] && SIG_NOTE="Developer ID (notarized)"   # manifest — 어드민 카탈로그 publish.signature 와 같게

export PATH="$FLUTTER_BIN:$HOME/.cargo/bin:$PATH"
export VCPKG_ROOT="$HOME/vcpkg"
export WALDLUST_HEARTBEAT_URL="http://127.0.0.1:9/api/heartbeat"
if [ "$TARGET" = mock ]; then
  export WALDLUST_HEARTBEAT_URL="http://127.0.0.1:8787/api/heartbeat"
  export WALDLUST_API_SERVER="http://127.0.0.1:8787/rd"
fi
if [ -n "$PROD" ]; then
  export WALDLUST_HEARTBEAT_URL="https://remote.waldpay.co.kr/api/heartbeat"
  export WALDLUST_API_SERVER="https://remote.waldpay.co.kr/rd"
fi
unset WALDLUST_PRESET_PASSWORD WALDLUST_VARIANT

step() { echo "== $1 $(date +%T)"; }
die() { echo "FAIL: $1 (로그: $LOG)"; exit 1; }
# 공증: 제출하고 끝날 때까지 기다린 뒤 결과·Apple 로그를 $LOG/macos-notary-<이름>*.json 에 남긴다. Accepted 가 아니면 멈춘다.
notarize() {
  local out="$LOG/macos-notary-$2.json" st id
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 1h --output-format json > "$out" 2>> "$LOG/macos-notary.log"
  st=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$out" 2>/dev/null)
  id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$out" 2>/dev/null)
  [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$LOG/macos-notary-$2-log.json" >> "$LOG/macos-notary.log" 2>&1
  [ "$st" = Accepted ] || die "공증 실패($2: ${st:-응답 없음}) — $LOG/macos-notary-$2-log.json"
  echo "notarized $2: $id"
}

xcodebuild -version >/dev/null 2>&1 || die "Xcode 가 선택되지 않았거나 라이선스 미동의(sudo xcode-select -s …, sudo xcodebuild -license accept)"

# release: origin(waldlustpos)에 있는 wald-v* 태그이고 로컬 태그와 같은 커밋이어야 한다.
if [ "$TARGET" = release ]; then
  [[ "$BASE" =~ '^wald-v[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$' ]] || die "release 는 wald-v<버전>-r<N> 태그만 받는다(받은 값: $BASE)"
  rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE^{}" | awk '{print $1}')
  [ -n "$rc" ] || rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE" | awk '{print $1}')
  lc=$(git -C "$R" rev-parse -q --verify "$BASE^{commit}")
  [ -n "$rc" ] && [ "$rc" = "$lc" ] || die "태그 $BASE 가 origin 에 없거나 로컬과 다르다(origin ${rc:-없음}, 로컬 ${lc:-없음})"
  [ -x "$HOME/.cargo/bin/cargo-about" ] || die "cargo-about 이 없다(cargo install cargo-about --version 0.6.4 --locked)"
  security find-identity -v -p codesigning | grep -qF "\"$SIGN_ID\"" || die "서명 인증서가 keychain 에 없다: $SIGN_ID"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
    die "공증 프로필 $NOTARY_PROFILE 이 없거나 동작하지 않는다(xcrun notarytool store-credentials)"
fi

# 0) worktree 를 새로 만든다(공용 작업 폴더와 분리). target 은 worktree 밖에 두고 심볼릭 링크한다.
#    Xcode 프로젝트가 ../../target/release/liblibrustdesk.dylib 를, build.py 가 target/release/service 를 참조한다.
step "worktree $BASE"
[ -d "$W" ] && git -C "$R" worktree remove --force "$W"
git -C "$R" worktree add --detach "$W" "$BASE" >/dev/null || die worktree
want=$(git -C "$R" ls-tree "$BASE" libs/hbb_common | awk '{print $3}')
have=$(git -C "$R/libs/hbb_common" rev-parse HEAD)
[ "$want" = "$have" ] || die "hbb_common 커밋 불일치(기준 $want, 공용 폴더 $have) — 공용 폴더에서 submodule update 필요"
rsync -a --exclude .git "$R/libs/hbb_common/" "$W/libs/hbb_common/" || die "submodule 복사"
mkdir -p "$OUT/target-macos"
ln -s "$OUT/target-macos" "$W/target" || die "target 링크"
cd "$W" || die cd
if [ "$TARGET" = release ]; then
  TAG_VER=${${BASE#wald-v}%-r*}
  SRC_VER=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
  CARGO_VER=$(grep -m1 -E '^version *=' Cargo.toml | cut -d'"' -f2)
  [ "$TAG_VER" = "$SRC_VER" ] && [ "$TAG_VER" = "$CARGO_VER" ] || die "태그 버전($TAG_VER)과 소스 버전(pubspec $SRC_VER, Cargo.toml $CARGO_VER)이 다르다"
fi

# 1) 브리지 생성. CI 는 Flutter 3.22.3 으로 만들지만, 로컬에서는 본 빌드와 같은 3.24.5 로 만들어 검증했다(pubspec 의 extended_text 는 이미 13.0.0).
#    ffigen 의 libclang 은 brew llvm(keg-only)을 경로로 넘긴다. 브리지는 CI 처럼 Rust 1.75 로 만든다.
step bridge
( export RUSTUP_TOOLCHAIN=1.75
  (cd flutter && flutter pub get) &&
  flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart \
    --c-output ./flutter/macos/Runner/bridge_generated.h --llvm-path /opt/homebrew/opt/llvm
) > "$LOG/macos-bridge.log" 2>&1 || die bridge
cp flutter/macos/Runner/bridge_generated.h flutter/ios/Runner/bridge_generated.h

# 2) vcpkg 의존성(arm64-osx). 설치돼 있으면 금방 끝난다.
step vcpkg
"$VCPKG_ROOT/vcpkg" install --x-install-root="$VCPKG_ROOT/installed" > "$LOG/macos-vcpkg.log" 2>&1 || die vcpkg

# 3) 빌드(wald-macos.yml 재현). 최소 macOS 를 12.3 으로 올리는 sed 는 worktree 안에서만 한다.
#    Xcode 27 은 배포 타깃 12.0 미만을 오류로 막는다. Pods 타깃(FMDB 10.13, 플러그인 10.14 등)까지 12.3 으로 맞추려고
#    FLUTTER_XCODE_MACOSX_DEPLOYMENT_TARGET 을 준다(Flutter 가 xcodebuild 명령줄 설정으로 넘겨 모든 타깃에 적용된다).
step build
sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET=[0-9]*\.[0-9]*/MACOSX_DEPLOYMENT_TARGET=${MIN_MACOS_VERSION}/" build.py
sed -i '' -e "s/platform :osx, '.*'/platform :osx, '${MIN_MACOS_VERSION}'/" flutter/macos/Podfile
sed -i '' -e "s/osx_minimum_system_version = \"[0-9]*\.[0-9]*\"/osx_minimum_system_version = \"${MIN_MACOS_VERSION}\"/" Cargo.toml
sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET = [0-9]*\.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = ${MIN_MACOS_VERSION};/" flutter/macos/Runner.xcodeproj/project.pbxproj
( export RUSTUP_TOOLCHAIN=1.81 FLUTTER_XCODE_MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS_VERSION
  python3 build.py --flutter --hwcodec --unix-file-copy-paste --screencapturekit
) > "$LOG/macos-build.log" 2>&1 || die build

# 번들 이름 = 이 ref 의 PRODUCT_NAME(부록 A-34 부터 'Waldlust 원격지원' — 공백이 있어 늘 따옴표로 쓴다, 그 전 ref 는 wald-remote).
APP_BUNDLE="$(sed -n 's/^PRODUCT_NAME = //p' flutter/macos/Runner/Configs/AppInfo.xcconfig).app"
APP="flutter/build/macos/Build/Products/Release/$APP_BUNDLE"
[ -d "$APP" ] || die "앱 번들이 없다: $APP"

# 3-1) release: 오픈소스 고지(D35)를 앱 Resources 에 넣는다 — 서명 전에(넣은 뒤 서명해야 봉인이 맞는다).
if [ "$TARGET" = release ]; then
  step notices
  NOTICES="$LOG/THIRD_PARTY_NOTICES-macos.txt"
  python3 res/wald-build/collect-notices.py --platform macos --out "$NOTICES" --release "$BASE" \
    --flutter-notices "$APP/Contents/Frameworks/App.framework/Resources/flutter_assets/NOTICES.Z" \
    --vcpkg-share "$VCPKG_ROOT/installed/arm64-osx/share" --cargo-about "$HOME/.cargo/bin/cargo-about" \
    > "$LOG/macos-notices.log" 2>&1 || die notices
  cp NOTICE "$APP/Contents/Resources/NOTICE.txt" && cp LICENCE "$APP/Contents/Resources/LICENCE.txt" &&
    cp "$NOTICES" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt" || die "고지 파일 복사"
fi

# 4) 재서명: build.py 가 flutter 서명 뒤에 service 를 복사해 번들 서명이 깨진다(CI 와 같은 처리).
#    시험본은 ad-hoc. release 는 Developer ID — --deep 대신 안쪽(프레임워크·dylib → 보조 실행 파일 → 앱)부터 서명한다
#    (--force 재서명은 엔타이틀먼트를 버리므로 실행 파일에 Release.entitlements 를 다시 준다). 그다음 앱을 공증·스테이플한다.
step sign
if [ "$TARGET" = release ]; then
  ENT=flutter/macos/Runner/Release.entitlements
  CS=(codesign --force --options runtime --timestamp --sign "$SIGN_ID")
  MAIN_EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
  : > "$LOG/macos-sign.log"
  for f in "$APP"/Contents/Frameworks/*.framework(N) "$APP"/Contents/Frameworks/*.dylib(N); do
    "${CS[@]}" "$f" >> "$LOG/macos-sign.log" 2>&1 || die "서명 ${f:t}"
  done
  for f in "$APP"/Contents/MacOS/*(N); do
    [ "${f:t}" = "$MAIN_EXE" ] && continue
    "${CS[@]}" --entitlements "$ENT" "$f" >> "$LOG/macos-sign.log" 2>&1 || die "서명 ${f:t}"
  done
  "${CS[@]}" --entitlements "$ENT" "$APP" >> "$LOG/macos-sign.log" 2>&1 || die "서명 앱"
  codesign --verify --deep --strict "$APP" >> "$LOG/macos-sign.log" 2>&1 || die "서명 검증"
  step notarize-app
  ZIP="$OUT/notary-app-macos.zip"; rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP" || die "공증용 zip"
  notarize "$ZIP" app
  rm -f "$ZIP"
  xcrun stapler staple "$APP" >> "$LOG/macos-notary.log" 2>&1 || die "앱 스테이플"
else
  codesign --force --deep --sign - "$APP" > "$LOG/macos-sign.log" 2>&1 || die sign
  codesign --verify --deep --strict "$APP" >> "$LOG/macos-sign.log" 2>&1 || die "서명 검증"
fi
VER=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
DEST="$OUT/waldlust-$VER-macos-$KIND$SUFFIX.app"
pgrep -f "$DEST/Contents/MacOS/" >/dev/null && die "$DEST 가 실행 중이다 — 종료한 뒤 다시 돌린다"
rm -rf "$DEST"
ditto "$APP" "$DEST" || die "앱 복사"

# 5) 확인: 아키텍처·최소 OS, heartbeat 주소(기대값 1 이상, 운영 0 — prodtest 는 기대값이 곧 운영), API 서버를 넣었으면 그 값(1 이상).
step verify
DYLIB="$DEST/Contents/Frameworks/liblibrustdesk.dylib"
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$DEST/Contents/Info.plist")   # 부록 A-34 부터 번들 이름과 다르다(Waldlust)
echo "arch: $(lipo -archs "$DEST/Contents/MacOS/$EXE") / minos: $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$DEST/Contents/Info.plist")"
HB_NEEDLE="${WALDLUST_HEARTBEAT_URL#*://}"
API_URL="${WALDLUST_API_SERVER:-}"; API_URL="${API_URL%/}"; API_NEEDLE="${API_URL#*://}"
hb=$(strings -a "$DYLIB" | grep -cF "$HB_NEEDLE")
prod=$(strings -a "$DYLIB" | grep -c 'remote.waldpay.co.kr/api/heartbeat')
api=-1; [ -n "$API_NEEDLE" ] && api=$(strings -a "$DYLIB" | grep -cF "$API_NEEDLE")
CHECK="heartbeat $HB_NEEDLE=$hb production=$prod / api-server ${API_NEEDLE:--}=$api"
echo "$CHECK"
{ [ "$hb" -ge 1 ] && { [ "$prod" -eq 0 ] || [ -n "$PROD" ]; }; } || die "heartbeat 주소 확인 실패 — 이 앱은 실행하지 않는다"
[ -z "$API_NEEDLE" ] || [ "$api" -ge 1 ] || die "API 서버 값이 빌드에 없다 — 이 앱은 실행하지 않는다"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
SCHEMES=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes' "$DEST/Contents/Info.plist" | tr -d ' {}\n' | sed 's/Array//')
echo "bundle id: $BUNDLE_ID / url scheme: $SCHEMES"
if [ "$TARGET" = release ]; then
  [ "$BUNDLE_ID" = co.kr.waldlust.remote ] && [ "$SCHEMES" = waldlust ] || die "번들 ID·URL 스킴이 정식 값이 아니다(D35)"
  for f in NOTICE.txt LICENCE.txt THIRD_PARTY_NOTICES.txt; do
    [ -s "$DEST/Contents/Resources/$f" ] || die "고지 파일 $f 가 앱에 없다"
  done
fi
echo "done: $DEST"

# 6) dmg(wald-macos.yml 'Create unsigned dmg' 와 같은 인자)를 dist/<버전>-<sha9>-<대상>/ 에 manifest 와 함께 모은다.
#    시험본은 대상 이름을 파일명에 넣어 배포본으로 착각하지 않게 한다(build-windows-local.ps1 -Inno 와 같은 규칙 — D36).
#    create-dmg 는 원본을 폴더로 다루므로(cd "$2") 앱 번들 하나만 든 폴더를 넘긴다.
#    Finder AppleScript(창 배치)가 권한 문제로 실패하면 배치 없이(--skip-jenkins) 다시 만든다.
step dmg
COMMIT=$(git rev-parse HEAD)
DIST="$OUT/dist/$VER-${COMMIT[1,9]}-$TARGET"
mkdir -p "$DIST"
DMG="$DIST/waldlust-remote$SUFFIX-$VER-macos-arm64$TSUF.dmg"
DMG_NOTE=""
STAGE="$OUT/dmg-stage-macos"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_BUNDLE" || die "dmg 원본 복사"
DMG_ARGS=(--icon "$APP_BUNDLE" 200 190 --hide-extension "$APP_BUNDLE" --window-size 800 400 --app-drop-link 600 185)
if ! create-dmg "${DMG_ARGS[@]}" "$DMG" "$STAGE" > "$LOG/macos-dmg.log" 2>&1; then
  rm -f "$DMG"
  create-dmg --skip-jenkins "${DMG_ARGS[@]}" "$DMG" "$STAGE" >> "$LOG/macos-dmg.log" 2>&1 || die dmg
  DMG_NOTE=" (Finder 창 배치 생략 — --skip-jenkins)"
fi
rm -rf "$STAGE"
if [ "$TARGET" = release ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG" >> "$LOG/macos-dmg.log" 2>&1 || die "dmg 서명"
  step notarize-dmg
  notarize "$DMG" dmg
  xcrun stapler staple "$DMG" >> "$LOG/macos-notary.log" 2>&1 || die "dmg 스테이플"
fi
hdiutil verify "$DMG" >> "$LOG/macos-dmg.log" 2>&1 || die "dmg 검증"
if [ "$TARGET" = release ]; then
  # Gatekeeper 판정: 앱은 'Notarized Developer ID', dmg 는 열기 허용이어야 한다.
  spctl -a -t exec -vv "$DEST" > "$LOG/macos-gatekeeper.log" 2>&1 && grep -q 'Notarized Developer ID' "$LOG/macos-gatekeeper.log" || die "앱 Gatekeeper 판정"
  spctl -a -t open --context context:primary-signature -vv "$DMG" >> "$LOG/macos-gatekeeper.log" 2>&1 || die "dmg Gatekeeper 판정"
  xcrun stapler validate "$DMG" >> "$LOG/macos-gatekeeper.log" 2>&1 || die "dmg 스테이플 확인"
  cat "$LOG/macos-gatekeeper.log"
fi
{
  echo "ref: $BASE ($COMMIT)"
  echo "platform: macos-aarch64"
  echo "variant: $VARIANT"
  echo "target: $TARGET"
  echo "api-server: ${WALDLUST_API_SERVER:-(none - account features disabled)}"
  echo "heartbeat: $WALDLUST_HEARTBEAT_URL"
  echo "check: $CHECK"
  echo "bundle id: $BUNDLE_ID / url scheme: $SCHEMES"
  echo "signature: $SIG_NOTE"
  echo "dmg: ${DMG:t}$DMG_NOTE"
  echo "size: $(stat -f %z "$DMG")"
  echo "sha256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
  echo "built: $(date '+%Y-%m-%d %H:%M:%S')"
} > "$DIST/manifest-macos-$VARIANT.txt"
if [ "$TARGET" = release ]; then
  cp NOTICE "$DIST/NOTICE.txt" && cp LICENCE "$DIST/LICENCE.txt" && cp "$NOTICES" "$DIST/THIRD_PARTY_NOTICES-macos.txt" || die "dist 고지 복사"
fi
echo "dmg: $DMG$DMG_NOTE"
if [ "$TARGET" = release ]; then
  echo "첫 실행: Developer ID 서명·공증본이라 Gatekeeper 경고 없이 열린다. 화면 기록·손쉬운 사용 권한은 시스템 설정에서 허용(서명 주체가 같으면 업데이트 뒤에도 유지)."
else
  echo "첫 실행: 미서명(ad-hoc) 앱이라 막히면 시스템 설정 > 개인정보 보호 및 보안 > '그래도 열기'. 화면 기록·손쉬운 사용 권한은 시스템 설정에서 허용."
fi
