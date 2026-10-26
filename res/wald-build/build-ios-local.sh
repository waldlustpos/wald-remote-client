#!/bin/zsh
# Waldlust(wald-remote-client) iOS 로컬 빌드 — Apple Silicon 호스트. arm64 시뮬레이터 앱과 기기용 .ipa(Ad Hoc·Development 서명, 명세 DSK-12, 인계 DSK-12_MOBILE.md §3·§6).
# CI 원본: .github/workflows/flutter-build.yml 의 iOS 잡(기기 aarch64-apple-ios — 업스트림에는 시뮬레이터 경로가 없다).
#
# 사용:  zsh ~/wald-build/build-ios-local.sh [커밋·브랜치·태그] [dummy|mock|prodtest|release] [bidirectional|outgoing] [simulator|device] [adhoc|development|personal]
#        (기본 waldlust, mock, bidirectional, simulator, adhoc — release 는 device·outgoing 만, personal 은 release 아님)
#        ref 의 iOS 프로젝트에 Rust 링크 경로 변수(WALD_RUST_TARGET — feat/dsk-12-ios 7d402103c)가 있어야 한다.
# 결과:  simulator: ~/wald-build/dist/<버전>-<sha9>-<대상>/waldlust-remote[-mobile]-<버전>-ios-simulator-<대상>.app + manifest-ios-simulator-<변형>.txt
#          설치·실행: xcrun simctl install booted <app> && xcrun simctl launch booted co.kr.waldlust.remote
#        device:    ~/wald-build/dist/<버전>-<sha9>-<대상>/waldlust-remote[-mobile]-<버전>-ios[-<대상>].ipa + manifest-ios-<변형>.txt
#          (release 는 대상 이름을 붙이지 않는다 — D36. outgoing = 모바일, 설치 파일 이름 '-mobile' — D43 (5))
#          Ad Hoc 또는 Development 서명 — 프로필에 등록한 iPhone 에만 설치된다(Finder·Apple Configurator 로 .ipa 를 끌어 놓는다).
#        로그: ~/wald-build/logs/ios-*.log
#
# 원칙(build-macos-local.sh 와 같다)
# - 비관리 빌드: WALDLUST_PRESET_PASSWORD 를 넣지 않는다(넣으면 폰이 접속 비밀번호를 만들어 보고한다). 변형은 bidirectional·outgoing
#   (발신 전용 — 직원 폰, 인계 §4.6. Rust 프리셋 conn-type outgoing·heartbeat variant "outgoing" 뿐이다 — 폰 UI 의 outgoing
#   분기는 모두 isAndroid 라 iOS 화면은 같다. iOS 는 원래 피제어 서버를 띄우지 않는다).
# - 운영 어드민에 보고하지 않는다: heartbeat 는 iOS 에서도 돈다(flutter_ffi initialize → global_init). 주소를 컴파일 때 넣는다.
#   dummy: http://127.0.0.1:9/api/heartbeat, WALDLUST_API_SERVER 는 호출자 값.
#   mock:  http://127.0.0.1:8787/api/heartbeat + WALDLUST_API_SERVER=http://127.0.0.1:8787/rd
#          (wald-remote-docs/tools/rd-mock — 시뮬레이터는 Mac 의 127.0.0.1 에 바로 닿는다. 앱을 띄우기 전에 먼저 띄운다)
#   prodtest: 운영 서버로 보내는 시험 빌드(macOS·Android 의 prodtest 와 같다 — 결정 C4). heartbeat = https://remote.waldpay.co.kr/api/heartbeat,
#          WALDLUST_API_SERVER = https://remote.waldpay.co.kr/rd. 운영 어드민 목록에 '미지정'으로 올라간다. 현장 배포용이 아니다.
#   release: 정식 모바일 배포본(결정 D43 — 2026-10-23 사용자: 1.5.6 r2 부터, Ad Hoc → 10-26 배포 인증서 한도로 Development). 주소는 prodtest 와 같다.
#          ref 는 waldlustpos(origin)에 푸시된 wald-v<버전>-r<N> 태그만, 태그 버전 = 소스 버전(D36).
#          CFBundleVersion(빌드 번호) = Android versionCode 와 같은 식 M×1,000,000 + m×10,000 + p×100 + r.
#          dist 에 NOTICE·LICENCE·THIRD_PARTY_NOTICES-ios.txt(cargo-about 0.6.4 필요).
#   heartbeat 담당 포트(127.0.0.1:47635)는 시뮬레이터와 Mac 이 같이 쓴다 — Mac 에서 Waldlust 앱이 돌고 있으면 시뮬레이터 앱은 보내지 않고 기다린다.
# - 공용 작업 폴더는 건드리지 않는다. worktree ~/wald-build/wt-ios(매번 새로), cargo target ~/wald-build/target-ios,
#   vcpkg 도구 ~/vcpkg-ios(120deac — macOS ~/vcpkg·Android ~/vcpkg-android 와 루트 잠금이 안 부딪힌다),
#   설치 루트 시뮬레이터 ~/vcpkg-ios-sim · 기기 ~/vcpkg-ios-dev(둘 다 폴더 이름이 arm64-ios 라 루트를 나눈다).
# - 전역 Flutter 설정(~/.config/flutter/settings)은 iOS 를 꺼 두었다(enable-ios false). 이 스크립트만 XDG_CONFIG_HOME 으로 켠다.
#
# 기기(device) 서명 — 다섯째 인자(2026-10-23 사용자 결정: App Store Connect API 팀 키로 자격을 만든다)
# - adhoc: login keychain 의 'Apple Distribution: Waldlust Co., Ltd. (GFY79GHBW8)' + ~/wald-build/keys/ios-adhoc.mobileprovision,
#   내보내기 release-testing, get-task-allow false·aps-environment production.
# - development(2026-10-26 사용자 결정 — 팀 배포 인증서가 한도 3개라 새로 못 만든다): 'Apple Development: …' +
#   ~/wald-build/keys/ios-development.mobileprovision, 내보내기 debugging, get-task-allow true·aps-environment development.
# - 자격은 ios-adhoc-signing.py [--development] --apply 가 만든다(App ID co.kr.waldlust.remote, 등록 기기). 기기를 더하면 프로필을 다시 만든다.
#   서명 ID 는 이름이 아니라 프로필 안 인증서의 SHA-1 로 keychain 에서 찾는다.
# - personal(2026-10-26 사용자 결정 — 회사 팀은 iPhone 등록 한도라 개인 폰을 못 넣는다): Xcode > 설정 > 계정에 넣은 개인 Apple ID 의
#   무료 팀으로 자동 서명. 시험 전용(release 안 됨) — 번들 ID co.kr.waldlust.remote.devtest(정식본과 따로 깔린다), 엔타이틀먼트 비움
#   (무료 팀은 푸시를 못 쓴다 — Wi-Fi 정보도 뺀다), 프로필 7일·기기 등록은 xcodebuild -allowProvisioningDeviceRegistration 이 한다.
#   Mac 에 연결한 iPhone 하나(둘 이상이면 WALD_IOS_DEVICE=<UDID>), 개인 팀이 둘 이상이면 WALD_IOS_PERSONAL_TEAM. 결과는 .app —
#   xcrun devicectl device install app --device <UDID> <app>, 첫 실행 전 iPhone 설정 > 일반 > VPN 및 기기 관리에서 개발자 앱 신뢰.
# - 포크의 Xcode 프로젝트는 자동 서명 그대로 두고, 빌드 worktree 의 Runner 타깃 설정에만 수동 서명(인증서·프로필 이름)을 넣는다.
#
# 시뮬레이터에서만 생기는 것과 처리(포크 소스·vcpkg 포트는 고치지 않는다 — 기기·다른 OS 빌드 그대로)
# ① Rust build.rs(scrap·magnum-opus·hwcodec)가 iOS 의 vcpkg 폴더를 installed/arm64-ios 로만 찾는다(-sim 구분 없음)
#    → overlay 트리플렛 vcpkg-triplets-ios-sim/arm64-ios.cmake(시뮬레이터 SDK, 최소 15.0)로 ~/vcpkg-ios-sim 에 설치하고
#      cargo 단계만 VCPKG_ROOT=~/vcpkg-ios-sim.
# ② libvpx 포트는 iOS 를 늘 기기 대상(arm64-darwin-gcc, iphoneos SDK)으로 빌드한다 → .a 오브젝트 플랫폼을 검사해
#    기기용(2)만 vtool 로 시뮬레이터(7)로 바꾼다(manifest 'retargeted').
# ③ ffmpeg iOS 포트는 기기 플래그 고정 → 시뮬레이터는 hwcodec 없이 빌드하고(업스트림 flutter/ios_x64.sh 와 같다)
#    worktree vcpkg.json 에서 대상 ffmpeg 항목을 뺀다.
# ④ libsodium-sys 0.2.7 은 aarch64-apple-ios-sim 을 몰라 panic → 동봉 1.0.18 을 시뮬레이터 SDK 로 한 번 빌드해 cargo 의 links 재정의
#    ([target.aarch64-apple-ios-sim.sodium])로 준다. SODIUM_LIB_DIR 은 쓰지 않는다 — 호스트(macOS)용 libsodium-sys(build.rs 가
#    hbb_common 을 쓴다)에도 적용돼 macOS 빌드 스크립트에 시뮬레이터 라이브러리가 링크된다.
# ⑤ coreaudio-sys 0.2.15 가 bindgen 에 --target=aarch64-apple-ios-sim 을 그대로 넘겨 clang 이 거부한다
#    → BINDGEN_EXTRA_CLANG_ARGS_aarch64_apple_ios_sim 으로 clang 대상(arm64-apple-ios15.0-simulator)을 뒤에 덧붙인다.
# 기기는 업스트림처럼 hwcodec(대상 ffmpeg 포함)으로 빌드한다. 트리플렛은 기기 SDK·최소 15.0 overlay 를 이 스크립트가 만든다
# (커뮤니티 arm64-ios 는 배포 타깃이 없어 SDK 기본값 — iOS 27 — 이 된다). libsodium 은 ④와 같은 방식을 기기 SDK 로 한다
# (libsodium-sys 0.2.7 build.rs 는 -mios-version-min=6.0.0 으로 빌드한다 — Xcode 27 SDK 의 최소값보다 낮다).
#
# 전제(한 번 설치해 둔 것): Xcode 27(iOS 27 시뮬레이터 런타임 — xcodebuild -downloadPlatform iOS), build-macos-local.sh 의 전제
#   (brew llvm cocoapods cmake nasm pkgconf, rustup 1.75, flutter_rust_bridge_codegen 1.80.1, ~/fvm/versions/3.24.5 CI 패치),
#   rustup target add aarch64-apple-ios-sim aarch64-apple-ios --toolchain 1.75,
#   ~/vcpkg-ios(git clone vcpkg → checkout 120deac3062162151622ca4860575a33844ba10b → bootstrap-vcpkg.sh -disableMetrics),
#   ~/wald-build/flutter-config-ios/flutter/settings({"enable-windows-desktop": false, "enable-ios": true}) + flutter precache --ios
set -u
R=/Users/kimsungchun/Documents/GitHub/wald-remote-client
OUT="$HOME/wald-build"
W="$OUT/wt-ios"
HERE="${0:A:h}"   # ~/wald-build 의 링크를 따라간 문서 저장소 wald-build
LOG="$OUT/logs"; mkdir -p "$LOG"
KEYS="$OUT/keys"
BASE="${1:-waldlust}"
TARGET="${2:-mock}"
VARIANT="${3:-bidirectional}"
MODE="${4:-simulator}"
SIGNING="${5:-adhoc}"
case "$TARGET" in dummy|mock|prodtest|release) ;; *) echo "FAIL: 대상은 dummy·mock·prodtest·release"; exit 1 ;; esac
case "$VARIANT" in bidirectional|outgoing) ;; *) echo "FAIL: 변형은 bidirectional·outgoing"; exit 1 ;; esac
case "$MODE" in simulator|device) ;; *) echo "FAIL: 넷째 인자는 simulator·device"; exit 1 ;; esac
case "$SIGNING" in adhoc|development|personal) ;; *) echo "FAIL: 다섯째 인자는 adhoc·development·personal"; exit 1 ;; esac
if [ "$SIGNING" = personal ]; then
  [ "$TARGET" != release ] || { echo "FAIL: personal(개인 팀) 서명은 시험 전용 — release 안 됨"; exit 1; }
  [ "$MODE" = device ] || { echo "FAIL: personal 은 기기(device) 빌드만"; exit 1; }
fi
if [ "$TARGET" = release ]; then
  [ "$VARIANT" = outgoing ] || { echo "FAIL: iOS release 는 모바일(outgoing)만 — D43"; exit 1; }
  [ "${4:-device}" = device ] || { echo "FAIL: release 는 기기(device) 빌드만"; exit 1; }
  MODE=device
fi
SUFFIX=""; [ "$VARIANT" = outgoing ] && SUFFIX="-mobile"   # D43 (5) — 설치 파일 이름, 변형 이름은 outgoing 그대로
TSUF="-$TARGET"; [ "$TARGET" = release ] && TSUF=""         # D36 — 정식본은 대상 이름 없음
PROD=""; { [ "$TARGET" = prodtest ] || [ "$TARGET" = release ]; } && PROD=1   # 운영 주소로 빌드한다
FLUTTER_BIN="$HOME/fvm/versions/3.24.5/bin"
MIN_IOS=15.0
TEAM=GFY79GHBW8                 # personal 이면 signing 단계에서 개인 팀으로 바뀐다
APP_BUNDLE=co.kr.waldlust.remote
if [ "$SIGNING" = personal ]; then
  SIGN_KIND="Apple Development"; P_KIND="Personal Team"; WANT_GTA=true; SIGN_ID=""; APP_BUNDLE=co.kr.waldlust.remote.devtest
elif [ "$SIGNING" = development ]; then
  SIGN_KIND="Apple Development"; P_KIND=Development; PROFILE_SRC="$KEYS/ios-development.mobileprovision"
  EXPORT_METHOD=debugging; WANT_GTA=true; WANT_APS=development; SIGN_ID=""   # 이름은 인증서마다 다르다 — 프로필에서 찾는다
else
  SIGN_KIND="Apple Distribution"; P_KIND="Ad Hoc"; PROFILE_SRC="$KEYS/ios-adhoc.mobileprovision"
  EXPORT_METHOD=release-testing; WANT_GTA=false; WANT_APS=production; SIGN_ID="Apple Distribution: Waldlust Co., Ltd. ($TEAM)"
fi
VCPKG_TOOL="$HOME/vcpkg-ios"
if [ "$MODE" = device ]; then
  RUST_TARGET=aarch64-apple-ios; SDK_NAME=iphoneos; INST_ROOT="$HOME/vcpkg-ios-dev"; WANT_PLAT=2
  SODIUM_DIR="$OUT/ios-native/libsodium-dev"; FEATURES=flutter,hwcodec
  TRIPLETS="$OUT/ios-native/triplets-device"
else
  RUST_TARGET=aarch64-apple-ios-sim; SDK_NAME=iphonesimulator; INST_ROOT="$HOME/vcpkg-ios-sim"; WANT_PLAT=7
  SODIUM_DIR="$OUT/ios-native/libsodium-sim"; FEATURES=flutter
  TRIPLETS="$HERE/vcpkg-triplets-ios-sim"
fi

export PATH="$FLUTTER_BIN:$HOME/.cargo/bin:$PATH"
export XDG_CONFIG_HOME="$OUT/flutter-config-ios"
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
[ "$VARIANT" = outgoing ] && export WALDLUST_VARIANT=outgoing   # build.rs·wald_variant.rs 가 읽는다(cargo 가 값 바뀜을 추적해 다시 빌드)

step() { echo "== $1 $(date +%T)"; }
die() { echo "FAIL: $1 (로그: $LOG)"; exit 1; }
# .a 안 오브젝트들의 플랫폼 번호(1 macOS, 2 iOS 기기, 7 iOS 시뮬레이터). 옛 LC_VERSION_MIN_IPHONEOS 는 기기(2)다.
platforms() {
  otool -l "$1" 2>/dev/null | awk '/cmd LC_BUILD_VERSION/{b=1; next} b && $1=="platform"{print $2; b=0} /cmd LC_VERSION_MIN_IPHONEOS/{print 2}' | sort -u | tr '\n' ' '
}
# 기기용 오브젝트를 시뮬레이터용으로 표시만 바꾼다(같은 arm64 명령어 — C 코덱 라이브러리라 SDK 차이가 없다).
# libvpx 는 옛 LC_VERSION_MIN_IPHONEOS(16바이트)라 vtool 이 LC_BUILD_VERSION(24바이트)을 넣을 자리가 없다 →
# 같은 기기 플랫폼으로 ld -r 해 LC_BUILD_VERSION 으로 다시 쓴 뒤 vtool 로 플랫폼만 바꾼다(ld 는 플랫폼이 다른 입력을 거부한다).
retarget() {
  local a=$1 t
  [ -z "$(ar t "$a" | sort | uniq -d)" ] || return 1   # 같은 이름 멤버가 있으면 ar x 가 덮어쓴다
  t=$(mktemp -d) || return 1
  (cd "$t" && ar x "$a") || return 1
  for o in "$t"/*.o(N); do
    xcrun ld -r -arch arm64 -platform_version ios $MIN_IOS 27.0 -o "$o.r" "$o" > /dev/null 2>&1 &&
      xcrun vtool -arch arm64 -set-build-version iossim $MIN_IOS 27.0 -replace -output "$o" "$o.r" > /dev/null 2>&1 &&
      rm -f "$o.r" || return 1
  done
  rm -f "$a" && (cd "$t" && ar rcs "$a" *.o(N)) || return 1
  rm -rf "$t"
}
# 프로필(.mobileprovision)의 값 하나 — security cms 로 풀어 PlistBuddy 로 읽는다.
pval() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

xcodebuild -version >/dev/null 2>&1 || die "Xcode 가 선택되지 않았거나 라이선스 미동의"
[ "$MODE" = device ] || xcrun simctl list runtimes | grep -q 'iOS 27' || die "iOS 시뮬레이터 런타임이 없다(xcodebuild -downloadPlatform iOS)"
[ -x "$VCPKG_TOOL/vcpkg" ] || die "vcpkg 도구가 없다: $VCPKG_TOOL(머리 주석의 전제)"
rustup +1.75 target list --installed | grep -qx $RUST_TARGET || die "rustup target add $RUST_TARGET --toolchain 1.75"
grep -q '"enable-ios": true' "$XDG_CONFIG_HOME/flutter/settings" 2>/dev/null || die "iOS 를 켠 Flutter 설정이 없다: $XDG_CONFIG_HOME/flutter/settings"

# release: origin(waldlustpos)에 있는 wald-v* 태그·빌드 번호(D36)·cargo-about 을 빌드 전에 확인한다(build-android-local.sh 와 같다).
BUILD_NO=""
if [ "$TARGET" = release ]; then
  [[ "$BASE" =~ '^wald-v[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$' ]] || die "release 는 wald-v<버전>-r<N> 태그만 받는다(받은 값: $BASE)"
  rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE^{}" | awk '{print $1}')
  [ -n "$rc" ] || rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE" | awk '{print $1}')
  lc=$(git -C "$R" rev-parse -q --verify "$BASE^{commit}")
  [ -n "$rc" ] && [ "$rc" = "$lc" ] || die "태그 $BASE 가 origin 에 없거나 로컬과 다르다(origin ${rc:-없음}, 로컬 ${lc:-없음})"
  TAG_VER=${${BASE#wald-v}%-r*}; TAG_PARTS=(${(s:.:)TAG_VER}); TAG_R=${BASE##*-r}
  BUILD_NO=$(( TAG_PARTS[1]*1000000 + TAG_PARTS[2]*10000 + TAG_PARTS[3]*100 + TAG_R ))
  echo "CFBundleVersion $BUILD_NO ($BASE)"
  [ -x "$HOME/.cargo/bin/cargo-about" ] || die "cargo-about 이 없다(cargo install cargo-about --version 0.6.4 --locked)"
fi

# 0) worktree 를 새로 만든다. Xcode 프로젝트가 ../../target/$(WALD_RUST_TARGET)/release/liblibrustdesk.a 를 링크한다.
step "worktree $BASE"
[ -d "$W" ] && git -C "$R" worktree remove --force "$W"
git -C "$R" worktree add --detach "$W" "$BASE" >/dev/null || die worktree
want=$(git -C "$R" ls-tree "$BASE" libs/hbb_common | awk '{print $3}')
have=$(git -C "$R/libs/hbb_common" rev-parse HEAD)
[ "$want" = "$have" ] || die "hbb_common 커밋 불일치(기준 $want, 공용 폴더 $have) — 공용 폴더에서 submodule update 필요"
rsync -a --exclude .git "$R/libs/hbb_common/" "$W/libs/hbb_common/" || die "submodule 복사"
mkdir -p "$OUT/target-ios"
ln -s "$OUT/target-ios" "$W/target" || die "target 링크"
cd "$W" || die cd
grep -q 'WALD_RUST_TARGET\[sdk=iphonesimulator' flutter/ios/Runner.xcodeproj/project.pbxproj ||
  die "이 ref 의 iOS 프로젝트에 Rust 링크 경로 변수가 없다(feat/dsk-12-ios 7d402103c 이후 ref 를 준다)"
[ "$VARIANT" != outgoing ] || [ -f res/wald-variant/outgoing.json ] || die "$BASE 에 발신 전용 변형(res/wald-variant/outgoing.json)이 없다"
VER=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
if [ "$TARGET" = release ]; then
  CARGO_VER=$(grep -m1 -E '^version *=' Cargo.toml | cut -d'"' -f2)
  [ "$TAG_VER" = "$VER" ] && [ "$TAG_VER" = "$CARGO_VER" ] || die "태그 버전($TAG_VER)과 소스 버전(pubspec $VER, Cargo.toml $CARGO_VER)이 다르다"
fi
[ -n "$BUILD_NO" ] || BUILD_NO=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f2)

# 1) 브리지(build-macos-local.sh 와 같다 — Rust 1.75, brew llvm). iOS 는 macOS 헤더를 복사해 쓴다(bridge.yml 과 같다).
step bridge
( export RUSTUP_TOOLCHAIN=1.75
  (cd flutter && flutter pub get) &&
  flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart \
    --c-output ./flutter/macos/Runner/bridge_generated.h --llvm-path /opt/homebrew/opt/llvm
) > "$LOG/ios-bridge.log" 2>&1 || die bridge
cp flutter/macos/Runner/bridge_generated.h flutter/ios/Runner/bridge_generated.h || die "브리지 헤더 복사"

# 2) vcpkg. 시뮬레이터(처리 ①②③): 대상 ffmpeg 는 worktree 의 vcpkg.json 에서만 뺀다(host ffmpeg 는 그대로 — macOS 캐시).
#    기기: 대상 ffmpeg 포함(hwcodec), 기기 SDK·최소 15.0 overlay 트리플렛.
step "vcpkg $MODE"
if [ "$MODE" = device ]; then
  mkdir -p "$TRIPLETS"
  cat > "$TRIPLETS/arm64-ios.cmake" <<EOF
# build-ios-local.sh 가 만든다(기기). vcpkg 120deac triplets/community/arm64-ios.cmake + 기기 SDK·앱 배포 타깃.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphoneos)
set(VCPKG_OSX_DEPLOYMENT_TARGET $MIN_IOS)
EOF
else
python3 -I - vcpkg.json <<'PY' || die "vcpkg.json 에서 대상 ffmpeg 빼기"
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
deps = [x for x in d["dependencies"] if not (isinstance(x, dict) and x.get("name") == "ffmpeg" and x.get("host") is False)]
assert len(deps) == len(d["dependencies"]) - 1, "target ffmpeg entry not found"
d["dependencies"] = deps
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
PY
fi
VCPKG_ROOT="$VCPKG_TOOL" "$VCPKG_TOOL/vcpkg" install --triplet arm64-ios --x-install-root="$INST_ROOT/installed" \
  --overlay-triplets="$TRIPLETS" > "$LOG/ios-vcpkg-$MODE.log" 2>&1 || die vcpkg
RETARGETED=()
for a in "$INST_ROOT"/installed/arm64-ios/lib/*.a(N); do
  p=$(platforms "$a")
  if [ "$MODE" = simulator ] && [[ " $p" == *" 2 "* ]]; then
    retarget "$a" || die "플랫폼 재지정 실패: ${a:t}"
    RETARGETED+=("${a:t}")
    p=$(platforms "$a")
  fi
  [ -z "$p" ] || [ "$p" = "$WANT_PLAT " ] || die "$MODE 용이 아닌 오브젝트가 있다: ${a:t} (플랫폼 $p)"
done
[ "$MODE" = simulator ] || [ -f "$INST_ROOT/installed/arm64-ios/lib/libavcodec.a" ] || die "기기 ffmpeg(libavcodec.a)가 없다"
[ "$MODE" = simulator ] && echo "retargeted: ${RETARGETED[*]:-(none)}"

# 3) libsodium(처리 ④ — 기기도 같은 방식) — 표식은 결과 파일. 동봉 소스를 임시 폴더에 복사해 빌드한다(cargo registry 를 더럽히지 않게).
step libsodium
if [ ! -f "$SODIUM_DIR/lib/libsodium.a" ]; then
  SRC=$(ls -d "$HOME"/.cargo/registry/src/*/libsodium-sys-0.2.7/libsodium(N) | head -1)
  [ -n "$SRC" ] || die "libsodium-sys 0.2.7 소스가 없다(공용 폴더에서 cargo fetch)"
  SDK=$(xcrun --sdk $SDK_NAME --show-sdk-path)
  MINFLAG="-mios-simulator-version-min=$MIN_IOS"; [ "$MODE" = device ] && MINFLAG="-miphoneos-version-min=$MIN_IOS"
  T=$(mktemp -d)
  cp -R "$SRC" "$T/src" || die "libsodium 소스 복사"
  ( cd "$T/src" &&
    ./configure --host=arm-apple-darwin20 --prefix="$SODIUM_DIR" --disable-shared --enable-static \
      CC="$(xcrun --sdk $SDK_NAME -f clang)" \
      CFLAGS="-O2 -arch arm64 -isysroot $SDK $MINFLAG" \
      LDFLAGS="-arch arm64 -isysroot $SDK $MINFLAG" &&
    make -j8 install
  ) > "$LOG/ios-libsodium-$MODE.log" 2>&1 || die libsodium
  rm -rf "$T"
fi
[ "$(platforms "$SODIUM_DIR/lib/libsodium.a")" = "$WANT_PLAT " ] || die "libsodium 이 $MODE 용이 아니다"

# 4) Rust. 시뮬레이터는 hwcodec 없음(처리 ③), 기기는 업스트림처럼 hwcodec.
#    hwcodec·scrap 은 vcpkg 정적 라이브러리를 rlib 에 묶어서 매번 다시 빌드한다(Android 와 같은 교훈).
step "cargo $RUST_TARGET ($FEATURES)"
( export RUSTUP_TOOLCHAIN=1.75 VCPKG_ROOT="$INST_ROOT" IPHONEOS_DEPLOYMENT_TARGET=$MIN_IOS
  SODIUM=(--config "target.$RUST_TARGET.sodium.rustc-link-lib=[\"static=sodium\"]"
          --config "target.$RUST_TARGET.sodium.rustc-link-search=[\"native=$SODIUM_DIR/lib\"]")   # 처리 ④
  export BINDGEN_EXTRA_CLANG_ARGS_aarch64_apple_ios_sim="--target=arm64-apple-ios$MIN_IOS-simulator"   # 처리 ⑤
  CLEAN=(-p scrap -p magnum-opus); [ "$MODE" = device ] && CLEAN+=(-p hwcodec)
  { cargo clean --release --target $RUST_TARGET "${CLEAN[@]}" || true; } &&
  cargo build "${SODIUM[@]}" --locked --features $FEATURES --release --target $RUST_TARGET --lib
) > "$LOG/ios-cargo-$MODE.log" 2>&1 || die cargo
[ -f "target/$RUST_TARGET/release/liblibrustdesk.a" ] || die "liblibrustdesk.a 가 없다"

# 기기: 서명 자격(ios-adhoc-signing.py 가 만든 것)을 확인하고 프로필을 Xcode 에 설치한다. 네이티브(vcpkg·Rust)는 자격 없이도 먼저 빌드된다.
# personal 은 Xcode 계정의 개인(무료) 팀과 연결된 iPhone 을 찾는다 — 프로필은 xcodebuild 가 만든다.
if [ "$MODE" = device ] && [ "$SIGNING" = personal ]; then
  step "signing (personal team)"
  PTEAMS=$(defaults export com.apple.dt.Xcode - 2>/dev/null | python3 -I -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
for teams in (d.get("IDEProvisioningTeamByIdentifier") or {}).values():
    for t in teams:
        if t.get("isFreeProvisioningTeam"):
            print(t.get("teamID"))
' | sort -u)
  if [ -z "$PTEAMS" ]; then
    # Xcode 27 은 팀 목록을 환경설정에 남기지 않는다 → keychain 의 'Apple Development' 서명 ID 중 회사 팀이 아닌 인증서의 OU(= 팀 ID).
    # 개인 팀 인증서는 Xcode > 설정 > Apple Accounts > Manage Certificates… > + > Apple Development 로 만든다.
    PTEAMS=$(security find-identity -v -p codesigning | awk -F'"' '/"Apple Development: /{print $2}' | while read -r n; do
      security find-certificate -c "$n" -p | openssl x509 -noout -subject -nameopt multiline | awk -F' = ' '/organizationalUnitName/{print $2}'
    done | grep -vx "$TEAM" | sort -u)
  fi
  TEAM="${WALD_IOS_PERSONAL_TEAM:-}"
  if [ -z "$TEAM" ]; then
    n=$(grep -c . <<< "$PTEAMS")
    [ "$n" -eq 1 ] || die "개인(무료) 팀이 하나가 아니다($n) — Xcode > 설정 > Apple Accounts 에 개인 Apple ID 를 넣고 Manage Certificates… > + > Apple Development, 또는 WALD_IOS_PERSONAL_TEAM"
    TEAM=$PTEAMS
  fi
  DJ="$LOG/ios-devices.json"
  xcrun devicectl list devices --json-output "$DJ" >/dev/null 2>&1 || die "devicectl list devices"
  DINFO=$(python3 -I - "$DJ" "${WALD_IOS_DEVICE:-}" <<'PY'
import json, sys
want = sys.argv[2].upper()
devs = [x for x in json.load(open(sys.argv[1]))["result"]["devices"]
        if x.get("hardwareProperties", {}).get("reality") != "simulated" and x.get("hardwareProperties", {}).get("platform") == "iOS"]
if want:
    devs = [x for x in devs if x["hardwareProperties"].get("udid", "").upper() == want]
if len(devs) != 1:
    print(f"연결된 iPhone 이 하나가 아니다({len(devs)}) — 하나만 연결하거나 WALD_IOS_DEVICE=<UDID>", file=sys.stderr); sys.exit(1)
x = devs[0]
print(x["hardwareProperties"]["udid"]); print(x["deviceProperties"].get("developerModeStatus") or "unknown"); print(x["deviceProperties"].get("name"))
PY
  ) || die "설치할 iPhone 찾기(위 메시지)"
  DEV_UDID=${${(f)DINFO}[1]}; DEV_MODE=${${(f)DINFO}[2]}; DEV_NAME=${${(f)DINFO}[3]}
  [ "$DEV_MODE" != disabled ] || die "iPhone 개발자 모드가 꺼져 있다 — 설정 > 개인정보 보호 및 보안 > 개발자 모드"
  echo "personal team ${TEAM[1,3]}… / device $DEV_NAME (${DEV_UDID[1,8]}…, developer mode $DEV_MODE) / bundle $APP_BUNDLE"
elif [ "$MODE" = device ]; then
  step "signing"
  GEN_ARG=""; [ "$SIGNING" = development ] && GEN_ARG=" --development"
  IDS=$(security find-identity -v -p codesigning | grep -F "\"$SIGN_KIND: ")
  [ -n "$IDS" ] || die "keychain 에 '$SIGN_KIND' 서명 ID 가 없다(ios-adhoc-signing.py$GEN_ARG --apply)"
  [ -z "$SIGN_ID" ] || grep -qF "\"$SIGN_ID\"" <<< "$IDS" || die "keychain 에 '$SIGN_ID' 가 없다(ios-adhoc-signing.py --apply)"
  [ -f "$PROFILE_SRC" ] || die "$P_KIND 프로필이 없다: $PROFILE_SRC(ios-adhoc-signing.py$GEN_ARG --apply)"
  PLIST="$LOG/ios-profile.plist"
  security cms -D -i "$PROFILE_SRC" > "$PLIST" 2>/dev/null || die "프로필을 풀지 못했다"
  # 이름·UUID·만료(UTC)·기기 수·서명 인증서 SHA-1 을 한 줄씩. 종류(get-task-allow — Ad Hoc false·Development true, 전체 기기 아님)·
  # 기기 목록·팀·App ID·만료(하루 넘게 남음)·프로필 안 인증서가 keychain 의 '$SIGN_KIND' 인증서(SHA-1)인지 함께 본다.
  ID_SHA1=$(awk '{print $2}' <<< "$IDS"); [ -z "$SIGN_ID" ] || ID_SHA1=$(grep -F "\"$SIGN_ID\"" <<< "$IDS" | awk '{print $2}')
  PINFO=$(python3 -I - "$PLIST" "$TEAM" "$ID_SHA1" "$WANT_GTA" <<'PY'
import datetime, hashlib, plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
team, ids, gta = sys.argv[2], set(sys.argv[3].upper().split()), sys.argv[4] == "true"
def fail(m): print(m, file=sys.stderr); sys.exit(1)
if d.get("ProvisionsAllDevices"): fail("프로필이 전체 기기(Enterprise)용이다(ProvisionsAllDevices)")
if bool(d["Entitlements"].get("get-task-allow")) != gta: fail(f"프로필 종류가 다르다(get-task-allow {not gta})")
devs = d.get("ProvisionedDevices") or []
if not devs: fail("프로필에 등록 기기가 없다")
if d.get("TeamIdentifier", [None])[0] != team or d["Entitlements"].get("application-identifier") != f"{team}.co.kr.waldlust.remote":
    fail("프로필 팀·App ID 가 다르다")
exp = d["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
if exp < datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1): fail(f"프로필이 곧 만료되거나 만료됐다({exp:%Y-%m-%d})")
hit = sorted(ids & {hashlib.sha1(c).hexdigest().upper() for c in d.get("DeveloperCertificates", [])})
if not hit: fail("프로필의 인증서가 keychain 의 서명 인증서와 다르다")
print(d["Name"]); print(d["UUID"]); print(f"{exp:%Y-%m-%d}"); print(len(devs)); print(hit[0])
PY
  ) || die "프로필 확인 실패(위 메시지)"
  P_NAME=${${(f)PINFO}[1]}; P_UUID=${${(f)PINFO}[2]}; P_EXP=${${(f)PINFO}[3]}; P_DEVICES=${${(f)PINFO}[4]}; P_SHA1=${${(f)PINFO}[5]}
  SIGN_ID=$(grep -F " $P_SHA1 " <<< "$IDS" | head -1 | sed -E 's/^[^"]*"(.*)"$/\1/')
  [ -n "$SIGN_ID" ] || die "프로필 인증서(${P_SHA1[1,8]}…)의 서명 ID 이름을 못 찾았다"
  for pd in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    mkdir -p "$pd" && cp "$PROFILE_SRC" "$pd/$P_UUID.mobileprovision" || die "프로필 설치"
  done
  echo "profile: $P_NAME ($P_UUID) $P_KIND, devices $P_DEVICES, expires $P_EXP / signer $SIGN_ID"
fi

# 5) Flutter. 시뮬레이터는 debug 만 된다(Rust 라이브러리가 arm64 뿐이라 arm64 만). 기기는 release + Ad Hoc·Development 내보내기.
if [ "$MODE" = simulator ]; then
  step flutter
  ( cd flutter && FLUTTER_XCODE_ARCHS=arm64 flutter build ios --simulator --debug ) > "$LOG/ios-flutter.log" 2>&1 || die flutter
  APP="flutter/build/ios/iphonesimulator/Runner.app"
  [ -d "$APP" ] || die "앱 번들이 없다: $APP"
elif [ "$SIGNING" = personal ]; then
  step "flutter config + xcodebuild (personal team, build $BUILD_NO)"
  # 이 worktree 의 Runner 타깃 세 구성만 팀·번들 ID 를 바꾸고 엔타이틀먼트를 비운다(자동 서명 그대로). Flutter 는 프로젝트에
  # DEVELOPMENT_TEAM 이 있으면 -allowProvisioningUpdates 를 붙이지 않아 xcodebuild 를 직접 부른다(--config-only 가 pod 까지 한다).
  python3 -I - flutter/ios/Runner.xcodeproj/project.pbxproj "$TEAM" "$APP_BUNDLE" <<'PY' || die "Runner 타깃에 개인 팀 넣기"
import sys
p, team, bid = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
for a, b in (("DEVELOPMENT_TEAM = GFY79GHBW8;", f"DEVELOPMENT_TEAM = {team};"),
             ("PRODUCT_BUNDLE_IDENTIFIER = co.kr.waldlust.remote;", f"PRODUCT_BUNDLE_IDENTIFIER = {bid};")):
    assert s.count(a) == 3, f"Runner 타깃 구성이 3개가 아니다({a})"
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY
  cat > flutter/ios/Runner/Runner.entitlements <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
ENT
  ( cd flutter && flutter build ios --config-only --release --build-number="$BUILD_NO" ) > "$LOG/ios-flutter-config.log" 2>&1 || die "flutter config-only"
  DD="$W/flutter/build/ios-personal"
  ( cd flutter/ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release -destination "id=$DEV_UDID" \
      -derivedDataPath "$DD" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build ) > "$LOG/ios-xcodebuild-personal.log" 2>&1 ||
    die "xcodebuild(개인 팀) — ios-xcodebuild-personal.log 끝의 error(계정·기기 등록·개발자 모드)"
  APP="$DD/Build/Products/Release-iphoneos/Runner.app"
  [ -d "$APP" ] || die "앱 번들이 없다: $APP"
else
  step "flutter ipa (build $BUILD_NO)"
  # 수동 서명은 이 worktree 의 Runner 타깃 설정(번들 ID 가 있는 세 구성)에만 넣는다 — 포크 프로젝트는 자동 서명 그대로.
  python3 -I - flutter/ios/Runner.xcodeproj/project.pbxproj "$P_NAME" "$SIGN_KIND" <<'PY' || die "Runner 타깃에 수동 서명 넣기"
import re, sys
p, name, kind = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
anchor = "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n"
n = s.count(anchor)
assert n == 3, f"Runner 타깃 구성이 3개가 아니다({n})"
def add(m):
    ind = m.group(1)
    return (m.group(0) + f'{ind}CODE_SIGN_STYLE = Manual;\n{ind}"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "{kind}";\n'
            f'{ind}PROVISIONING_PROFILE_SPECIFIER = "{name}";\n')
s = re.sub(r"([ \t]*)" + re.escape(anchor), add, s)
open(p, "w", encoding="utf-8").write(s)
PY
  EXPORT_PLIST="$LOG/ios-export-options.plist"
  cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$EXPORT_METHOD</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$SIGN_KIND</string>
  <key>provisioningProfiles</key><dict><key>co.kr.waldlust.remote</key><string>$P_NAME</string></dict>
  <key>thinning</key><string>&lt;none&gt;</string>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
EOF
  plutil -lint "$EXPORT_PLIST" >/dev/null || die "ExportOptions plist"
  rm -rf flutter/build/ios/ipa
  ( cd flutter && flutter build ipa --release --build-number="$BUILD_NO" --export-options-plist="$EXPORT_PLIST" ) > "$LOG/ios-flutter-ipa.log" 2>&1 || die "flutter ipa"
  IPAS=(flutter/build/ios/ipa/*.ipa(N))
  [ ${#IPAS} -eq 1 ] || die "ipa 가 하나가 아니다(${#IPAS})"
  IPA="${IPAS[1]}"
  CHK="$LOG/ios-ipa-check"; rm -rf "$CHK"; mkdir -p "$CHK"
  ditto -x -k "$IPA" "$CHK" || die "ipa 풀기"
  APP="$CHK/Payload/Runner.app"
  [ -d "$APP" ] || die "ipa 안에 Runner.app 이 없다"
fi

# 6) 확인: heartbeat 주소(기대값 1 이상, 운영 0 — prodtest·release 는 기대값이 곧 운영), API 서버를 넣었으면 그 값(1 이상), 번들 ID·스킴, 플랫폼·최소 OS.
#    시뮬레이터 debug 빌드는 코드가 Runner.debug.dylib 로 갈 수 있어 앱 안 Mach-O 를 모두 본다.
#    기기는 버전·빌드 번호, 서명(인증서·Ad Hoc 또는 Development 프로필·엔타이틀먼트)까지 본다.
step verify
HB_NEEDLE="${WALDLUST_HEARTBEAT_URL#*://}"
API_URL="${WALDLUST_API_SERVER:-}"; API_URL="${API_URL%/}"; API_NEEDLE="${API_URL#*://}"
hb=0; prod=0; api=0
for m in "$APP/Runner" "$APP"/*.dylib(N); do
  s=$(strings -a "$m")
  hb=$((hb + $(grep -cF "$HB_NEEDLE" <<< "$s")))
  prod=$((prod + $(grep -c 'remote.waldpay.co.kr/api/heartbeat' <<< "$s")))
  [ -n "$API_NEEDLE" ] && api=$((api + $(grep -cF "$API_NEEDLE" <<< "$s")))
done
[ -n "$API_NEEDLE" ] || api=-1
CHECK="heartbeat $HB_NEEDLE=$hb production=$prod / api-server ${API_NEEDLE:--}=$api"
echo "$CHECK"
[ "$hb" -ge 1 ] && { [ "$prod" -eq 0 ] || [ -n "$PROD" ]; } || die "heartbeat 주소 확인 실패 — 이 앱은 실행하지 않는다"
[ -z "$API_NEEDLE" ] || [ "$api" -ge 1 ] || die "API 서버 값이 빌드에 없다 — 이 앱은 실행하지 않는다"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
SCHEMES=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes' "$APP/Info.plist" | tr -d ' {}\n' | sed 's/Array//')
BUILD_INFO=$(xcrun vtool -show-build "$APP/Runner" | awk '$1=="platform"||$1=="minos"{printf "%s %s ", $1, $2}')
echo "bundle id: $BUNDLE_ID / url scheme: $SCHEMES / $BUILD_INFO"
[ "$BUNDLE_ID" = "$APP_BUNDLE" ] && [ "$SCHEMES" = waldlust ] || die "번들 ID·URL 스킴이 기대값($APP_BUNDLE·waldlust)이 아니다"
WANT_BUILD=IOSSIMULATOR; [ "$MODE" = device ] && WANT_BUILD="platform IOS "
[[ "$BUILD_INFO" == *"$WANT_BUILD"* && "$BUILD_INFO" == *"minos $MIN_IOS"* ]] || die "플랫폼·최소 OS 가 기대값(${WANT_BUILD% }·$MIN_IOS)이 아니다"
if [ "$MODE" = device ]; then
  B_VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
  B_NO=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
  [ "$B_VER" = "$VER" ] && [ "$B_NO" = "$BUILD_NO" ] || die "버전·빌드 번호가 $VER($BUILD_NO)가 아니다($B_VER/$B_NO)"
  codesign --verify --deep --strict "$APP" 2> "$LOG/ios-codesign-verify.log" || die "codesign 검증 실패"
  AUTH=$(codesign -dvv "$APP" 2>&1 | grep -m1 '^Authority=' | cut -d= -f2-)
  if [ "$SIGNING" = personal ]; then
    [[ "$AUTH" == "Apple Development: "* ]] || die "서명자가 Apple Development 가 아니다($AUTH)"
  else
    [ "$AUTH" = "$SIGN_ID" ] || die "서명자가 '$SIGN_ID' 가 아니다($AUTH)"
  fi
  ENT="$LOG/ios-entitlements.plist"
  codesign -d --entitlements - --xml "$APP" > "$ENT" 2>/dev/null || die "엔타이틀먼트 읽기"
  [ "$(pval "$ENT" get-task-allow)" = "$WANT_GTA" ] || die "get-task-allow 가 $WANT_GTA 가 아니다($P_KIND 서명이 아님)"
  [ "$(pval "$ENT" application-identifier)" = "$TEAM.$APP_BUNDLE" ] || die "application-identifier 가 다르다"
  if [ "$SIGNING" != personal ]; then
    [ "$(pval "$ENT" aps-environment)" = "$WANT_APS" ] || die "aps-environment 가 $WANT_APS 가 아니다"
    [ "$(pval "$ENT" com.apple.developer.networking.wifi-info)" = true ] || die "wifi-info 엔타이틀먼트가 없다"
  fi
  EMB="$LOG/ios-embedded-profile.plist"
  security cms -D -i "$APP/embedded.mobileprovision" > "$EMB" 2>/dev/null || die "앱 안 프로필을 풀지 못했다"
  if [ "$SIGNING" = personal ]; then
    PINFO=$(python3 -I - "$EMB" "$DEV_UDID" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
devs = [u.upper() for u in d.get("ProvisionedDevices") or []]
if sys.argv[2].upper() not in devs:
    print("앱 안 프로필에 이 iPhone 이 없다", file=sys.stderr); sys.exit(1)
print(d["Name"]); print(d["UUID"]); print(f"{d['ExpirationDate']:%Y-%m-%d}"); print(len(devs))
PY
    ) || die "앱 안 프로필 확인(위 메시지)"
    P_NAME=${${(f)PINFO}[1]}; P_UUID=${${(f)PINFO}[2]}; P_EXP=${${(f)PINFO}[3]}; P_DEVICES=${${(f)PINFO}[4]}
  else
    [ "$(pval "$EMB" UUID)" = "$P_UUID" ] || die "앱 안 프로필이 $P_NAME 이 아니다"
  fi
  echo "signed: $AUTH / profile $P_NAME ($P_KIND, devices $P_DEVICES, expires $P_EXP) / version $B_VER ($B_NO)"
fi

# 7) dist/<버전>-<sha9>-<대상>/ 에 앱(.app 또는 .ipa)과 manifest 를 모은다.
step dist
COMMIT=$(git rev-parse HEAD)
DIST="$OUT/dist/$VER-${COMMIT[1,9]}-$TARGET"
mkdir -p "$DIST"
if [ "$MODE" = simulator ]; then
  DEST="$DIST/waldlust-remote$SUFFIX-$VER-ios-simulator-$TARGET.app"
  MAN="$DIST/manifest-ios-simulator-$VARIANT.txt"
  rm -rf "$DEST"
  ditto "$APP" "$DEST" || die "앱 복사"
elif [ "$SIGNING" = personal ]; then
  DEST="$DIST/waldlust-remote$SUFFIX-$VER-ios-personal-$TARGET.app"
  MAN="$DIST/manifest-ios-personal-$VARIANT.txt"
  rm -rf "$DEST"
  ditto "$APP" "$DEST" || die "앱 복사"
else
  DEST="$DIST/waldlust-remote$SUFFIX-$VER-ios$TSUF.ipa"
  MAN="$DIST/manifest-ios-$VARIANT.txt"
  cp "$IPA" "$DEST" || die "ipa 복사"
fi
{
  echo "ref: $BASE ($COMMIT)"
  if [ "$MODE" = simulator ]; then
    echo "platform: ios-simulator-arm64 (min iOS $MIN_IOS, debug — Flutter 는 시뮬레이터에서 debug 만)"
  else
    echo "platform: ios-arm64 (min iOS $MIN_IOS, release)"
  fi
  echo "variant: $VARIANT"
  echo "target: $TARGET"
  echo "api-server: ${WALDLUST_API_SERVER:-(none - account features disabled)}"
  echo "heartbeat: $WALDLUST_HEARTBEAT_URL"
  echo "check: $CHECK"
  echo "bundle id: $BUNDLE_ID / url scheme: $SCHEMES"
  if [ "$MODE" = simulator ]; then
    echo "cargo features: flutter (hwcodec 없음 — 시뮬레이터)"
    echo "simulator fixes: vcpkg overlay arm64-ios(sim) · target ffmpeg dropped · libsodium 1.0.18 links override · bindgen clang target · retargeted: ${RETARGETED[*]:-(none)}"
    echo "signature: none (simulator)"
  else
    echo "version: $B_VER ($B_NO)"
    echo "cargo features: $FEATURES"
    echo "signing: $SIGNING"
    echo "signer: $AUTH"
    echo "profile: $P_NAME ($P_UUID) — $P_KIND, devices $P_DEVICES, expires $P_EXP"
    if [ "$SIGNING" = personal ]; then
      echo "app: ${DEST:t} (personal team ${TEAM[1,3]}…, bundle $APP_BUNDLE — 시험 전용, 엔타이틀먼트 없음)"
      echo "size: $(du -sk "$DEST" | awk '{print $1}') KiB"
    else
      echo "ipa: ${DEST:t}"
      echo "size: $(stat -f %z "$DEST")"
      echo "sha256: $(shasum -a 256 "$DEST" | awk '{print $1}')"
    fi
  fi
  echo "built: $(date '+%Y-%m-%d %H:%M:%S')"
} > "$MAN"
# release: 오픈소스 고지(D35) — 앱 안 Flutter NOTICES, 기기 vcpkg, cargo-about.
if [ "$TARGET" = release ]; then
  step notices
  python3 res/wald-build/collect-notices.py --platform ios --out "$DIST/THIRD_PARTY_NOTICES-ios.txt" --release "$BASE" \
    --flutter-notices "$APP/Frameworks/App.framework/flutter_assets/NOTICES.Z" --vcpkg-share "$INST_ROOT/installed/arm64-ios/share" \
    --cargo-about "$HOME/.cargo/bin/cargo-about" > "$LOG/notices-ios.log" 2>&1 || die notices
  cp NOTICE "$DIST/NOTICE.txt" && cp LICENCE "$DIST/LICENCE.txt" || die "dist 고지 복사"
fi
echo "done: $DEST"
if [ "$MODE" = simulator ]; then
  echo "실행: xcrun simctl install booted \"$DEST\" && xcrun simctl launch booted co.kr.waldlust.remote"
  [ "$TARGET" = mock ] && echo "목업 대상이다 — 앱을 띄우기 전에 rd-mock(8787)을 띄운다"
elif [ "$SIGNING" = personal ]; then
  echo "설치: xcrun devicectl device install app --device $DEV_UDID \"$DEST\""
  echo "      첫 실행 전 iPhone 설정 > 일반 > VPN 및 기기 관리 > 개발자 앱 신뢰. 프로필 만료 $P_EXP(7일) — 지나면 다시 빌드·설치"
else
  echo "설치: 프로필에 등록한 iPhone 을 Mac 에 연결 → Finder 에서 기기를 고르고 .ipa 를 끌어 놓는다(또는 Apple Configurator)"
fi
exit 0
