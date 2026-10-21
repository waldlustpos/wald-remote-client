#!/bin/zsh
# Waldlust(wald-remote-client) Android APK 로컬 빌드 — macOS(arm64) 호스트.
# 2026-09-29 에 재현한 절차를 한 파일로 모은 것이다(명세 docs/HANDOVER_SPEC.md F-46).
# CI 원본: .github/workflows/wald-android.yml, .github/workflows/bridge.yml
#
# 사용:  zsh ~/wald-build/build-android-local.sh [커밋·브랜치] [bidirectional|incoming] [dummy|mock|prodtest|release]   (기본 waldlust, bidirectional, dummy)
# 결과:  ~/wald-build/waldlust-<버전>-android-localtest[-incoming].apk(prodtest 는 -android-prodtest), 로그는 ~/wald-build/logs/
#        + ~/wald-build/dist/<버전>-<sha9>-<대상>/waldlust-remote[-incoming]-<버전>-android[-<대상>].apk 와 manifest-android-<변형>.txt
#        (설치 파일 이름 규칙 — 결정 D36: release 는 '-<대상>' 을 붙이지 않는다. 예 waldlust-remote-incoming-1.5.0-android.apk)
#        수신 전용이면 도우미 앱(wald-helper — 부록 A-44, 결정 D39·D40)도 같은 버전·같은 서명으로 먼저 만들어 메인 APK 의
#        assets/wald-helper.apk 로 넣고(앱이 설치한다 — D40), 따로도 남긴다:
#        dist 의 waldlust-remote-helper-<버전>-android[-<대상>].apk 와 manifest-android-helper.txt. wald-helper 가 없는 옛 ref 는 건너뛴다.
#
# 원칙
# - 비관리 빌드: WALDLUST_PRESET_PASSWORD 를 넣지 않는다(무인 기본값·기기별 비밀번호 없음).
#   업그레이드 시험처럼 관리 빌드가 필요할 때만 WALD_TEST_MANAGED=1 로 표식(값은 표식일 뿐 비밀번호 아님)을 넣는다.
# - 운영 어드민에 보고하지 않는다: WALDLUST_HEARTBEAT_URL 을 컴파일 때 넣는다.
#   dummy: http://127.0.0.1:9/api/heartbeat. heartbeat 내용을 볼 때만 WALD_TEST_HEARTBEAT_URL 로 바꾼다.
#          WALDLUST_API_SERVER 는 호출자가 준 값을 그대로 쓴다.
#   mock:  http://127.0.0.1:8787/api/heartbeat + WALDLUST_API_SERVER=http://127.0.0.1:8787/rd(rd-mock, build-windows-local.ps1 -Target 과 같다).
#          기기에서는 `adb reverse tcp:8787 tcp:8787` 로 이 Mac 의 목업에 닿는다.
#   prodtest: 운영 서버로 보내는 시험 빌드(계획 ADMIN_LOCAL_PLAN C4, 결정 D16 — 2026-10-14 사용자). heartbeat = https://remote.waldpay.co.kr/api/heartbeat,
#          WALDLUST_API_SERVER = https://remote.waldpay.co.kr/rd. 비관리·ad-hoc 서명 그대로이고 현장 배포용이 아니다(저장소 이전 전 — REPO_TRANSITION).
#          시험 기기는 운영 목록에 '미지정'으로 올라간다. 결과 이름이 localtest 가 아니라 prodtest 라 dummy·mock 시험본을 덮지 않는다.
#          기기는 인터넷으로 운영에 닿는다(adb reverse 필요 없음). 수신 전용 비밀번호는 여전히 테스트 값이 기본이다.
#   release: 정식 배포본(계획 ADMIN_LOCAL_PLAN 4-1, 결정 D33~D35 — 2026-10-14 사용자). 주소는 prodtest 와 같다.
#          ref 는 waldlustpos(origin)에 푸시된 wald-v<버전>-r<N> 태그만 받는다(태그 버전 = 소스 버전이어야 한다 — D36).
#          수신 전용은 운영 공통 비밀번호(incoming-prod.env)만 받는다.
#          서명 = 릴리즈 키(~/wald-build/keys/android-release.properties — make-android-release-key.sh 가 만든다, debug 치환 안 함),
#          서명 지문은 ~/wald-build/keys/android-release.sha256 과 같아야 한다. versionCode 는 태그에서 계산한다(D36):
#          M×1,000,000 + m×10,000 + p×100 + r — wald-v1.5.0-r1 = 1050001(옛 규칙 2100+r 의 r3 = 2103 보다 크다).
#          WALD_VERSION_CODE 를 주면 계산값과 같아야 한다. 패키지 = co.kr.waldlust.remote(D35).
#          같은 버전 재게시(배포 공지 전 사내 시험 단계만 — 2026-10-20 사용자, 부록 A-44): WALD_REUSE_VCODE_OF=<같은 버전의 앞 태그>
#          (예 wald-v1.5.3-r1)를 주면 그 태그의 versionCode 를 그대로 쓴다. 이미 깐 기기는 같은 versionCode 라 덮어 설치된다.
#          dist 에 NOTICE·LICENCE·THIRD_PARTY_NOTICES-android.txt.
#          cargo-about 0.6.4(cargo install cargo-about --version 0.6.4 --locked)가 있어야 한다.
# - 수신 전용(DSK-01): ~/wald-build/incoming-test.env(git 밖, 권한 600)의 테스트 비밀번호·솔트
#   (WALDLUST_INCOMING_PASSWORD·WALDLUST_INCOMING_SALT — 운영 값 아님)를 preset_hash.py 로 해시해 넣는다. 값은 출력하지 않는다.
#   지문(저장 해시의 SHA-256 앞 5자)만 찍는다 — Windows set-incoming-env.ps1·build-windows-local.ps1 과 같은 값이어야 한다.
#   운영 공통 비밀번호로 빌드할 때만 WALD_INCOMING_ENV=~/wald-build/incoming-prod.env(set-incoming-password.sh 가 만든다)를 준다.
# - 공용 작업 폴더는 건드리지 않는다(다른 세션이 macOS 빌드를 할 수 있다). 모든 작업은 별도 git worktree 에서 하고,
#   vcpkg 루트(~/vcpkg-android)와 cargo target(~/wald-build/target-android)도 분리한다.
#   vcpkg 매니페스트 모드는 설치 루트를 트리플렛 하나가 차지해서, 같은 루트에 다른 트리플렛을 설치하면 기존 설치분이 purge 된다.
#
# 전제(한 번 설치해 둔 것):
#   rustup + 1.75(타깃 aarch64-linux-android, armv7-linux-androideabi),
#   cargo-ndk 3.1.2 / cargo-expand 1.0.95 / flutter_rust_bridge_codegen 1.80.1(--features uuid),
#   ~/flutter-sdks/3.22.3, ~/flutter-sdks/3.24.5(.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff 적용),
#   ~/vcpkg-android(120deac3062162151622ca4860575a33844ba10b, bootstrap 완료), Android SDK + NDK r28c(28.2.13676358),
#   JDK 17(brew openjdk@17), Xcode Command Line Tools, brew: nasm pkgconf autoconf automake libtool
#   xcode-select 가 Xcode.app 이어도 된다: 브리지(ffigen, CLT libclang)가 CLT SDK 를 쓰도록 DEVELOPER_DIR 기본값을 CLT 로 둔다.
set -u
R=/Users/kimsungchun/Documents/GitHub/wald-remote-client
OUT="$HOME/wald-build"
W="$OUT/wt-android"
LOG="$OUT/logs"; mkdir -p "$LOG"
BASE="${1:-waldlust}"
VARIANT="${2:-bidirectional}"
case "$VARIANT" in
  bidirectional) SUFFIX="" ;;
  incoming) SUFFIX="-incoming" ;;
  *) echo "FAIL: 변형은 bidirectional 또는 incoming"; exit 1 ;;
esac
TARGET="${3:-dummy}"
case "$TARGET" in dummy|mock|prodtest|release) ;; *) echo "FAIL: 대상은 dummy·mock·prodtest·release"; exit 1 ;; esac
KIND=localtest; [ "$TARGET" = prodtest ] && KIND=prodtest; [ "$TARGET" = release ] && KIND=release
PROD=""; { [ "$TARGET" = prodtest ] || [ "$TARGET" = release ]; } && PROD=1   # 운영 주소로 빌드한다
TSUF="-$TARGET"; [ "$TARGET" = release ] && TSUF=""   # dist 설치 파일 이름 끝(D36 — 정식본은 대상 이름 없음)
KEYS="$OUT/keys"

export PATH="$HOME/.cargo/bin:$PATH"
# Xcode 27 SDK 를 CLT libclang 이 못 읽어 브리지가 깨진다(uint8_t → Pointer<Int>). CLT SDK 를 쓰게 한다.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export RUSTUP_TOOLCHAIN=1.75               # CI(wald-android.yml)와 같은 Rust
export VCPKG_ROOT="$HOME/vcpkg-android"
export CARGO_TARGET_DIR="$OUT/target-android"
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME" ANDROID_NDK="$ANDROID_NDK_HOME"
export WALDLUST_HEARTBEAT_URL="${WALD_TEST_HEARTBEAT_URL:-http://127.0.0.1:9/api/heartbeat}"
if [ "$TARGET" = mock ]; then
  export WALDLUST_HEARTBEAT_URL="http://127.0.0.1:8787/api/heartbeat"
  export WALDLUST_API_SERVER="http://127.0.0.1:8787/rd"
fi
if [ -n "$PROD" ]; then
  export WALDLUST_HEARTBEAT_URL="https://remote.waldpay.co.kr/api/heartbeat"
  export WALDLUST_API_SERVER="https://remote.waldpay.co.kr/rd"
fi
unset WALDLUST_PRESET_PASSWORD WALDLUST_VARIANT WALDLUST_INCOMING_PW_STORAGE WALDLUST_INCOMING_PW_SALT
[ "${WALD_TEST_MANAGED:-}" = 1 ] && export WALDLUST_PRESET_PASSWORD=local-test-marker
# macOS: bindgen(kcp-sys, scrap 등)이 Android 헤더를 찾도록 NDK sysroot 를 준다. Linux CI 는 호스트 /usr/include 로 넘어간다.
export LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib
NDKSYS="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=$NDKSYS"
export BINDGEN_EXTRA_CLANG_ARGS_armv7_linux_androideabi="--sysroot=$NDKSYS"

step() { echo "== $1 $(date +%T)"; }
die() { echo "FAIL: $1 (로그: $LOG)"; exit 1; }

# release: origin(waldlustpos)에 있는 wald-v* 태그·릴리즈 키·versionCode·운영 비밀번호를 빌드 전에 확인한다.
if [ "$TARGET" = release ]; then
  [[ "$BASE" =~ '^wald-v[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$' ]] || die "release 는 wald-v<버전>-r<N> 태그만 받는다(받은 값: $BASE)"
  rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE^{}" | awk '{print $1}')
  [ -n "$rc" ] || rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE" | awk '{print $1}')
  lc=$(git -C "$R" rev-parse -q --verify "$BASE^{commit}")
  [ -n "$rc" ] && [ "$rc" = "$lc" ] || die "태그 $BASE 가 origin 에 없거나 로컬과 다르다(origin ${rc:-없음}, 로컬 ${lc:-없음})"
  [ -f "$KEYS/android-release.properties" ] && [ -s "$KEYS/android-release.sha256" ] || die "릴리즈 키가 없다($KEYS — make-android-release-key.sh)"
  TAG_VER=${${BASE#wald-v}%-r*}; TAG_PARTS=(${(s:.:)TAG_VER}); TAG_R=${BASE##*-r}
  VCODE=$(( TAG_PARTS[1]*1000000 + TAG_PARTS[2]*10000 + TAG_PARTS[3]*100 + TAG_R ))   # D36
  if [ -n "${WALD_REUSE_VCODE_OF:-}" ]; then
    REUSE_R=${WALD_REUSE_VCODE_OF##*-r}
    [[ "$WALD_REUSE_VCODE_OF" =~ "^wald-v${TAG_VER//./\\.}-r[0-9]+\$" ]] && (( REUSE_R < TAG_R )) \
      || die "WALD_REUSE_VCODE_OF 는 같은 버전의 앞 태그여야 한다(받은 값: $WALD_REUSE_VCODE_OF, 이번 $BASE)"
    git -C "$R" ls-remote --exit-code origin "refs/tags/$WALD_REUSE_VCODE_OF" >/dev/null || die "태그 $WALD_REUSE_VCODE_OF 가 origin 에 없다"
    VCODE=$(( VCODE - TAG_R + REUSE_R ))
    echo "versionCode 재사용: $WALD_REUSE_VCODE_OF 와 같은 값(같은 버전 재게시)"
  fi
  [ -z "${WALD_VERSION_CODE:-}" ] || [ "$WALD_VERSION_CODE" = "$VCODE" ] || die "WALD_VERSION_CODE($WALD_VERSION_CODE)가 태그에서 계산한 값($VCODE)과 다르다 — 빼고 돌린다"
  [ "$VCODE" -ge 2100 ] || die "versionCode $VCODE 는 2100 이상이어야 한다(옛 현장 설치본 2066)"
  echo "versionCode $VCODE ($BASE)"
  [ "$VARIANT" != incoming ] || [ "${${WALD_INCOMING_ENV:-}:t}" = incoming-prod.env ] || die "release 수신 전용은 WALD_INCOMING_ENV=$OUT/incoming-prod.env 만 받는다"
  [ -x "$HOME/.cargo/bin/cargo-about" ] || die "cargo-about 이 없다(cargo install cargo-about --version 0.6.4 --locked)"
fi

# 0) worktree 를 새로 만든다(공용 작업 폴더와 분리).
step "worktree $BASE"
[ -d "$W" ] && git -C "$R" worktree remove --force "$W"
git -C "$R" worktree add --detach "$W" "$BASE" >/dev/null || die worktree
# 서브모듈 hbb_common 은 Rust 빌드와 Gradle(app/build.gradle 의 `cargo metadata`, protos)이 쓴다. 공용 폴더의 체크아웃을 복사한다.
want=$(git -C "$R" ls-tree "$BASE" libs/hbb_common | awk '{print $3}')
have=$(git -C "$R/libs/hbb_common" rev-parse HEAD)
[ "$want" = "$have" ] || die "hbb_common 커밋 불일치(기준 $want, 공용 폴더 $have) — 공용 폴더에서 submodule update 필요"
rsync -a --exclude .git "$R/libs/hbb_common/" "$W/libs/hbb_common/" || die "submodule 복사"
cd "$W" || die cd
if [ "$TARGET" = release ]; then
  SRC_VER=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
  CARGO_VER=$(grep -m1 -E '^version *=' Cargo.toml | cut -d'"' -f2)
  [ "$TAG_VER" = "$SRC_VER" ] && [ "$TAG_VER" = "$CARGO_VER" ] || die "태그 버전($TAG_VER)과 소스 버전(pubspec $SRC_VER, Cargo.toml $CARGO_VER)이 다르다"
fi

# 수신 전용: 테스트 비밀번호를 해시로 바꿔 넣는다(평문은 하위 셸에만 있고 빌드 환경에는 들어가지 않는다).
if [ "$VARIANT" = incoming ]; then
  step "variant incoming"
  ENVF="${WALD_INCOMING_ENV:-$OUT/incoming-test.env}"   # 운영 값: WALD_INCOMING_ENV=$OUT/incoming-prod.env
  [ -f "$ENVF" ] || die "$ENVF 가 없다(WALDLUST_INCOMING_PASSWORD·WALDLUST_INCOMING_SALT)"
  [ -f res/wald-variant/preset_hash.py ] || die "$BASE 에 수신 전용 변형(res/wald-variant)이 없다"
  # 셸 해석 없이 한 줄씩 읽는다(비밀번호에 $ " 공백 등이 있어도 안전). 평문은 이 하위 셸에만 있다.
  hash_out=$( while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in WALDLUST_INCOMING_PASSWORD=*|WALDLUST_INCOMING_SALT=*) export "${line%%=*}=${line#*=}" ;; esac
              done < "$ENVF"
              python3 res/wald-variant/preset_hash.py ) || die "비밀번호 해시(preset_hash.py)"
  export WALDLUST_VARIANT=incoming
  # 수신 전용 아이콘(오른쪽 위 ↓ 배지, DSK-10). 이 기능이 없는 옛 ref 는 건너뛴다(build.rs 도 확인하지 않는다).
  if [ -f res/wald-variant/apply_icons.py ]; then
    python3 res/wald-variant/apply_icons.py || die "수신 전용 아이콘(apply_icons.py)"
  fi
  export WALDLUST_INCOMING_PW_STORAGE="${${(f)hash_out}[1]#*=}"
  export WALDLUST_INCOMING_PW_SALT="${${(f)hash_out}[2]#*=}"
  unset hash_out
  # 지문 = 저장 해시 문자열의 SHA-256 앞 5자(Windows 와 대조용). 비밀번호·해시 값은 찍지 않는다.
  FP=$(printf %s "$WALDLUST_INCOMING_PW_STORAGE" | shasum -a 256 | cut -c1-5)
  echo "incoming password fingerprint $FP ($ENVF)"
fi

# 1) 브리지 생성(bridge.yml 재현: Flutter 3.22.3 + extended_text 13 임시 다운그레이드).
#    macOS: ffigen 에 CLT libclang 경로와 SDK sysroot 를 넘겨야 한다(값이 '-' 로 시작하므로 '=' 형식).
step bridge
SDK=$(xcrun --show-sdk-path)
sed -i '' -e 's/extended_text: 14.0.0/extended_text: 13.0.0/g' flutter/pubspec.yaml
( export PATH="$HOME/flutter-sdks/3.22.3/bin:$PATH"
  (cd flutter && flutter pub get) &&
  flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart \
    --c-output ./flutter/macos/Runner/bridge_generated.h \
    --llvm-path /Library/Developer/CommandLineTools/usr "--llvm-compiler-opts=-isysroot $SDK"
) > "$LOG/bridge.log" 2>&1 || die bridge
cp flutter/macos/Runner/bridge_generated.h flutter/ios/Runner/bridge_generated.h
git checkout -- flutter/pubspec.yaml flutter/pubspec.lock

# 2) 네이티브 라이브러리: CI 처럼 ABI 마다 의존성 → Rust 순서로 번갈아 한다(9dc8c7c). 다음 트리플렛 설치가 앞 설치분을 지우기 때문이다.
step deps-arm64; ./flutter/build_android_deps.sh arm64-v8a  > "$LOG/deps-arm64.log" 2>&1 || die deps-arm64
# hwcodec·scrap 은 vcpkg 정적 라이브러리(FFmpeg 등)를 자기 rlib 에 묶는데 그 파일 변경은 감시하지 않는다. 공용 target 에 남은 옛 rlib 이
# 패치 전 FFmpeg 를 그대로 링크한다(2026-10-21 발견 — res/vcpkg/ffmpeg 패치가 APK 에 안 들어감). 매번 두 크레이트를 다시 빌드한다.
cargo clean -q -p hwcodec -p scrap --release --target aarch64-linux-android || die "cargo clean arm64"
step rust-arm64; ./flutter/ndk_arm64.sh                      > "$LOG/rust-arm64.log" 2>&1 || die rust-arm64
# build_android_deps.sh 는 installed/arm-neon-android 를 arm-android 로 mv 한다. arm-android 가 이미 있으면 그 안에 중첩되고
# armv7 Rust 는 옛 arm-android/{include,lib} 를 링크한다(2026-10-21 발견 — 09-29 설치분이 그대로 쓰였다). 그래서 통째로 지우고
# mv 가 이름을 바꾸게 한다(vcpkg 가 관리하는 트리플렛 폴더가 아니라 지워도 된다).
rm -rf "$VCPKG_ROOT/installed/arm-android"
step deps-armv7; ./flutter/build_android_deps.sh armeabi-v7a > "$LOG/deps-armv7.log" 2>&1 || die deps-armv7
[ -f "$VCPKG_ROOT/installed/arm-android/lib/libavcodec.a" ] && [ ! -d "$VCPKG_ROOT/installed/arm-android/arm-neon-android" ] \
  || die "deps-armv7 설치 위치(installed/arm-android)"
cargo clean -q -p hwcodec -p scrap --release --target armv7-linux-androideabi || die "cargo clean armv7"
step rust-armv7; ./flutter/ndk_arm.sh                        > "$LOG/rust-armv7.log" 2>&1 || die rust-armv7

# 2b) 수신 전용: 도우미 앱(wald-helper — 부록 A-44 1단계, 결정 D39·D40). 메인 앱과 같은 버전(정식은 태그의 versionCode)·같은 서명
#     (release = 릴리즈 키, 그 밖 = debug 키)으로 메인 APK 보다 먼저 만들어 메인 APK 의 assets/wald-helper.apk 로 넣는다(앱이 도우미를
#     설치한다 — D40). Flutter·Rust 없이 Gradle 만 쓴다. wald-helper 가 없는 옛 ref 는 건너뛴다.
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
VER=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
HAPK=""
if [ "$VARIANT" = incoming ] && [ -d wald-helper ]; then
  step helper
  HVCODE="${VCODE:-$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f2)}"
  echo "sdk.dir=$HOME/Library/Android/sdk" > wald-helper/local.properties
  [ "$TARGET" != release ] || cp "$KEYS/android-release.properties" wald-helper/key.properties || die "도우미 키 설정 복사"
  ( cd wald-helper && ./gradlew --no-daemon -q :app:assembleRelease -PwaldVersionCode="$HVCODE" -PwaldVersionName="$VER"
  ) > "$LOG/helper.log" 2>&1; hrc=$?
  rm -f wald-helper/key.properties   # release 에서 복사한 키 설정
  [ $hrc -eq 0 ] || die helper
  HAPK="$OUT/waldlust-$VER-android-$KIND-helper.apk"
  cp wald-helper/app/build/outputs/apk/release/app-release.apk "$HAPK" || die "도우미 APK 복사"
  mkdir -p flutter/android/app/src/main/assets
  cp "$HAPK" flutter/android/app/src/main/assets/wald-helper.apk || die "도우미를 메인 앱 assets 에 넣기"   # git 제외 파일(flutter/android/.gitignore)
fi

# 3) APK(Flutter 3.24.5). macOS: libc++_shared 는 darwin-x86_64 경로에서 가져오고, Gradle 7.6.4 는 JDK 17 로 고정한다.
#    Flutter 가 JAVA_HOME 보다 Android Studio JBR(21)을 우선하므로 worktree 의 gradle.properties 로 지정한다(전역 flutter config 는 건드리지 않는다).
step apk
J=flutter/android/app/src/main/jniLibs; L="$NDKSYS/usr/lib"
mkdir -p "$J/arm64-v8a" "$J/armeabi-v7a"
cp "$L/aarch64-linux-android/libc++_shared.so" "$J/arm64-v8a/" || die "libc++ arm64"
cp "$L/arm-linux-androideabi/libc++_shared.so" "$J/armeabi-v7a/" || die "libc++ armv7"
cp "$CARGO_TARGET_DIR/aarch64-linux-android/release/liblibrustdesk.so" "$J/arm64-v8a/librustdesk.so" || die "arm64 .so"
cp "$CARGO_TARGET_DIR/armv7-linux-androideabi/release/liblibrustdesk.so" "$J/armeabi-v7a/librustdesk.so" || die "armv7 .so"
sed -i '' 's/org.gradle.jvmargs=-Xmx1024M/org.gradle.jvmargs=-Xmx2g/g' flutter/android/gradle.properties   # CI 와 같은 임시 수정
BUILD_NUMBER=()
if [ "$TARGET" = release ]; then
  cp "$KEYS/android-release.properties" flutter/android/key.properties || die "릴리즈 키 설정 복사"   # worktree 안(git 제외 파일)
  BUILD_NUMBER=(--build-number="$VCODE")
else
  sed -i '' 's/signingConfigs.release/signingConfigs.debug/g' flutter/android/app/build.gradle              # CI 와 같은 debug 서명
fi
echo "org.gradle.java.home=$JAVA_HOME" >> flutter/android/gradle.properties
( export PATH="$JAVA_HOME/bin:$HOME/flutter-sdks/3.24.5/bin:$PATH"
  cd flutter && flutter build apk --release --target-platform android-arm,android-arm64 "${BUILD_NUMBER[@]}"
) > "$LOG/apk.log" 2>&1 || die apk
rm -f flutter/android/key.properties   # release 에서 복사한 키 설정(그 밖 대상에는 없다)
VER=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
APK="$OUT/waldlust-$VER-android-$KIND$SUFFIX.apk"
cp flutter/build/app/outputs/flutter-apk/app-release.apk "$APK" || die "APK 복사"


# 4) 확인: 정체·ABI·서명, ABI 마다 heartbeat 주소(기대값 1 이상, 운영 0 — prodtest 는 기대값이 곧 운영)와 API 서버를 넣었으면 그 값(1 이상).
step verify
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | tail -1)
BADGING=$("$BT/aapt2" dump badging "$APK")
echo "$BADGING" | grep -E "^package:|application-label:|native-code"
SIGNER=$("$BT/apksigner" verify --print-certs "$APK" | grep -E "Signer #1 certificate SHA-256" | awk '{print $NF}')
echo "Signer #1 certificate SHA-256: $SIGNER"
HB_NEEDLE="${WALDLUST_HEARTBEAT_URL#*://}"
API_URL="${WALDLUST_API_SERVER:-}"; API_URL="${API_URL%/}"; API_NEEDLE="${API_URL#*://}"
CHECK=""; BAD=""
for abi in arm64-v8a armeabi-v7a; do
  unzip -p "$APK" "lib/$abi/librustdesk.so" > "$LOG/check.so"
  hb=$(strings -a "$LOG/check.so" | grep -cF "$HB_NEEDLE")
  prod=$(strings -a "$LOG/check.so" | grep -c 'remote.waldpay.co.kr/api/heartbeat')
  api=-1; [ -n "$API_NEEDLE" ] && api=$(strings -a "$LOG/check.so" | grep -cF "$API_NEEDLE")
  line="$abi heartbeat $HB_NEEDLE=$hb production=$prod / api-server ${API_NEEDLE:--}=$api"
  echo "$line"; CHECK="${CHECK:+$CHECK; }$line"
  { [ "$hb" -ge 1 ] && { [ "$prod" -eq 0 ] || [ -n "$PROD" ]; } && { [ -z "$API_NEEDLE" ] || [ "$api" -ge 1 ]; }; } || BAD=1
done
rm -f "$LOG/check.so"
[ -z "$BAD" ] || die "heartbeat·API 주소 확인 실패 — 이 APK 는 설치하지 않는다"
PKG_LINE=$(echo "$BADGING" | grep -E '^package:')
if [ "$TARGET" = release ]; then
  [ "$SIGNER" = "$(tr -d ' \n' < "$KEYS/android-release.sha256")" ] || die "서명 지문이 릴리즈 키와 다르다 — 이 APK 는 배포하지 않는다"
  echo "$PKG_LINE" | grep -q "name='co.kr.waldlust.remote'" || die "패키지가 co.kr.waldlust.remote 가 아니다(D35)"
  echo "$PKG_LINE" | grep -q "versionCode='$VCODE'" || die "versionCode 가 $VCODE 가 아니다"
fi
echo "done: $APK"
if [ -n "$HAPK" ]; then
  HBADGING=$("$BT/aapt2" dump badging "$HAPK")
  HPKG_LINE=$(echo "$HBADGING" | grep -E '^package:')
  echo "helper $HPKG_LINE"
  HSIGNER=$("$BT/apksigner" verify --print-certs "$HAPK" | grep -E "Signer #1 certificate SHA-256" | awk '{print $NF}')
  [ -n "$HSIGNER" ] && [ "$HSIGNER" = "$SIGNER" ] || die "도우미 서명이 메인 앱과 다르다 — 이 APK 는 배포하지 않는다"
  echo "$HPKG_LINE" | grep -q "name='co.kr.waldlust.remote.helper'" || die "도우미 패키지가 co.kr.waldlust.remote.helper 가 아니다"
  echo "$HPKG_LINE" | grep -q "versionCode='$HVCODE'" || die "도우미 versionCode 가 $HVCODE 가 아니다"
  # 2단계(부록 A-44, 결정 D41): 도우미가 입력 제어(접근성)·입력 브리지를 갖췄는지, 메인 앱이 브리지 서명 권한을 쓰는지.
  # 1단계 도우미(옛 ref)는 브리지가 없다 — 그때는 표시만 한다.
  HXML=$("$BT/aapt2" dump xmltree --file AndroidManifest.xml "$HAPK")
  if echo "$HXML" | grep -q 'co.kr.waldlust.remote.helper.INPUT_BRIDGE'; then
    echo "$HXML" | grep -q 'android.accessibilityservice' || die "도우미에 입력 브리지는 있는데 접근성 서비스가 없다"
    "$BT/aapt2" dump permissions "$APK" | grep -q 'co.kr.waldlust.remote.permission.INPUT_BRIDGE' \
      || die "메인 앱이 도우미 입력 브리지 권한(INPUT_BRIDGE)을 쓰지 않는다"
    echo "helper input control: accessibility + INPUT_BRIDGE"
  else
    echo "helper input control: none (stage-1 helper)"
  fi
  # 메인 APK 안 사본(assets/wald-helper.apk — 앱이 설치하는 것, D40)이 이 도우미와 같은 파일인지
  [ "$(unzip -p "$APK" assets/wald-helper.apk | shasum -a 256 | awk '{print $1}')" = "$(shasum -a 256 "$HAPK" | awk '{print $1}')" ] \
    || die "메인 APK 의 assets/wald-helper.apk 가 도우미 APK 와 다르다"
  echo "helper bundled in main APK: assets/wald-helper.apk"
  echo "done: $HAPK"
fi

# 5) dist/<버전>-<sha9>-<대상>/ 에 APK 와 manifest 를 모은다. 시험본은 이름에 대상을 붙인다(build-windows-local.ps1 -Inno 와 같은 규칙 — D36).
step dist
COMMIT=$(git rev-parse HEAD)
DIST="$OUT/dist/$VER-${COMMIT[1,9]}-$TARGET"
mkdir -p "$DIST"
DAPK="$DIST/waldlust-remote$SUFFIX-$VER-android$TSUF.apk"
cp "$APK" "$DAPK" || die "dist 복사"
{
  echo "ref: $BASE ($COMMIT)"
  echo "platform: android (arm64-v8a, armeabi-v7a)"
  echo "variant: $VARIANT"
  echo "target: $TARGET"
  echo "api-server: ${WALDLUST_API_SERVER:-(none - account features disabled)}"
  echo "heartbeat: $WALDLUST_HEARTBEAT_URL"
  echo "check: $CHECK"
  [ "$VARIANT" = incoming ] && echo "incoming password fingerprint: $FP"
  echo "package: $(echo "$BADGING" | grep -E '^package:' | sed -E "s/.*name='([^']*)'.*versionCode='([^']*)'.*versionName='([^']*)'.*/\1 versionCode=\2 versionName=\3/")"
  echo "signer sha256: $SIGNER"
  [ "$TARGET" = release ] && echo "signing: release key ($KEYS/android-release.properties)"
  [ -n "${WALD_REUSE_VCODE_OF:-}" ] && echo "versionCode reused from: $WALD_REUSE_VCODE_OF (same-version republish)"
  echo "apk: ${DAPK:t}"
  echo "size: $(stat -f %z "$DAPK")"
  echo "sha256: $(shasum -a 256 "$DAPK" | awk '{print $1}')"
  echo "built: $(date '+%Y-%m-%d %H:%M:%S')"
} > "$DIST/manifest-android-$VARIANT.txt"
if [ -n "$HAPK" ]; then
  HDAPK="$DIST/waldlust-remote-helper-$VER-android$TSUF.apk"
  cp "$HAPK" "$HDAPK" || die "dist 도우미 복사"
  {
    echo "ref: $BASE ($COMMIT)"
    echo "platform: android (no native code)"
    echo "variant: helper"
    echo "target: $TARGET"
    echo "package: $(echo "$HPKG_LINE" | sed -E "s/.*name='([^']*)'.*versionCode='([^']*)'.*versionName='([^']*)'.*/\1 versionCode=\2 versionName=\3/")"
    echo "signer sha256: $HSIGNER"
    [ "$TARGET" = release ] && echo "signing: release key ($KEYS/android-release.properties)"
    echo "apk: ${HDAPK:t}"
    echo "size: $(stat -f %z "$HDAPK")"
    echo "sha256: $(shasum -a 256 "$HDAPK" | awk '{print $1}')"
    echo "built: $(date '+%Y-%m-%d %H:%M:%S')"
  } > "$DIST/manifest-android-helper.txt"
fi
# 6) release: 오픈소스 고지(D35)를 dist 에 둔다. APK 안의 Flutter NOTICES 와 vcpkg(arm-android — 마지막 ABI, 포트 구성은 두 ABI 가 같다).
if [ "$TARGET" = release ]; then
  step notices
  python3 res/wald-build/collect-notices.py --platform android --out "$DIST/THIRD_PARTY_NOTICES-android.txt" --release "$BASE" \
    --flutter-notices "$DAPK" --vcpkg-share "$VCPKG_ROOT/installed/arm-android/share" --cargo-about "$HOME/.cargo/bin/cargo-about" \
    > "$LOG/notices-android.log" 2>&1 || die notices
  cp NOTICE "$DIST/NOTICE.txt" && cp LICENCE "$DIST/LICENCE.txt" || die "dist 고지 복사"
fi
echo "dist: $DAPK"
[ -n "$HAPK" ] && echo "dist: $HDAPK"
if [ "$TARGET" = release ]; then
  echo "주의: 앱 ID 가 co.kr.waldlust.remote 로 바뀌었다(D35) — 옛 앱(com.carriez.flutter_hbb)은 따로 지운다. 새 설치는 ID 가 새로 생긴다."
else
  echo "주의: versionCode 는 pubspec 값(현재 66)이다. 기존 설치(2066)는 제자리 업데이트가 안 되고 지웠다 깔아야 한다 — 명세 F-46."
fi
