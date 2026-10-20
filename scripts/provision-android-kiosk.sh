#!/usr/bin/env bash
# Waldlust 안드로이드 무인 키오스크 프로비저닝 (박스당 1회)
#
# 이 스크립트가 하는 일:
#   1) APK 설치(선택) — 이미 깔려 있으면 --apk 생략
#   2) 앱을 1회 실행 → 안드로이드 "stopped-state" 해제(안 하면 재부팅해도 BOOT_COMPLETED 안 옴)
#      + MainActivity 가 "부팅 시 시작"을 기본 ON 으로 세팅
#   3) 무인 동작에 필요한 표준 권한을 부여:
#        - 접근성 InputService 활성화(입력)
#        - 배터리 최적화 화이트리스트(백그라운드 유지)
#        - 다른 앱 위에 표시(오버레이) — BootReceiver 통과 조건
#   4) 재부팅 → 이후 전원만 켜면 온라인 + 화면 + 입력이 사람 손 없이 동작
#
# 화면공유(MediaProjection) 팝업은 앱 내부의 접근성 서비스가 자동 클릭하므로 여기선 따로 안 건드림.
# 전제: 박스가 루팅(또는 adb 로 secure settings 쓰기 가능)돼 있어야 함. Magisk 는 이 앱/shell 에
#       su 자동 허용(무프롬프트)으로 설정할 것.
#
# 사용:
#   ./provision-android-kiosk.sh                 # 연결된 기기 1대
#   ./provision-android-kiosk.sh --serial <SN>   # 특정 기기
#   ./provision-android-kiosk.sh --apk waldlust.apk   # 설치까지
set -euo pipefail

# 앱 ID(co.kr.waldlust.remote)와 클래스 네임스페이스(com.carriez.flutter_hbb)가 다르다 — 클래스는 전체 이름으로(Q-29, D35)
PKG="co.kr.waldlust.remote"
NS="com.carriez.flutter_hbb"
ACCESS_SVC="$PKG/$NS.InputService"
MAIN_ACT="$PKG/$NS.MainActivity"
# 원격지원 도우미(DSK-02 — 2단계, 결정 D41): 도우미에 입력 제어(접근성)가 있으면 그쪽을 켠다(앱을 강제 종료해도 남는다).
HELPER_PKG="co.kr.waldlust.remote.helper"
HELPER_SVC="$HELPER_PKG/$HELPER_PKG.InputService"

SERIAL=""
APK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2;;
    --apk) APK="$2"; shift 2;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done
ADB=(adb)
[ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")

echo "== 대상 기기 =="; "${ADB[@]}" get-state

if [ -n "$APK" ]; then
  echo "== APK 설치: $APK =="
  "${ADB[@]}" install -r -g "$APK" || "${ADB[@]}" install -r "$APK"
fi

echo "== 1) 앱 1회 실행 (stopped-state 해제 + 부팅시작 기본 ON) =="
"${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || \
  "${ADB[@]}" shell am start -n "$MAIN_ACT" >/dev/null 2>&1 || true
sleep 3

echo "== 2) 접근성(입력) 활성화 =="
if "${ADB[@]}" shell dumpsys package "$HELPER_PKG" 2>/dev/null | grep -q "$HELPER_PKG.InputService"; then
  ACCESS_SVC="$HELPER_SVC"
  # 아이콘 없는 도우미는 새로 설치하면 stopped — 신호로 푼다(원격 앱이 켜질 때도 푼다)
  "${ADB[@]}" shell am broadcast -f 0x20 -a "$HELPER_PKG.ACTIVATE" -n "$HELPER_PKG/.BootReceiver" >/dev/null 2>&1 || true
  echo "- 도우미 입력 제어 사용: $ACCESS_SVC"
fi
CUR="$("${ADB[@]}" shell settings get secure enabled_accessibility_services | tr -d '\r')"
if [ "$CUR" = "null" ] || [ -z "$CUR" ]; then NEW="$ACCESS_SVC"; else
  case "$CUR" in *"$ACCESS_SVC"*) NEW="$CUR";; *) NEW="$CUR:$ACCESS_SVC";; esac
fi
"${ADB[@]}" shell settings put secure enabled_accessibility_services "$NEW"
"${ADB[@]}" shell settings put secure accessibility_enabled 1

echo "== 3) 배터리 최적화 예외 + 오버레이 허용 =="
"${ADB[@]}" shell dumpsys deviceidle whitelist +$PKG >/dev/null 2>&1 || true
"${ADB[@]}" shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow || true
# (참고) 화면공유 appop 은 팝업을 못 건너뛰므로 설정하지 않음 — 앱이 접근성으로 자동 승인.

echo "== 4) 확인 =="
echo "- 접근성:"; "${ADB[@]}" shell settings get secure enabled_accessibility_services | tr -d '\r'
echo "- 오버레이(SYSTEM_ALERT_WINDOW):"; "${ADB[@]}" shell appops get "$PKG" SYSTEM_ALERT_WINDOW | tr -d '\r'

echo
echo "완료. 이제 기기를 재부팅해 테스트하세요:"
echo "    ${ADB[*]} reboot"
echo "재부팅 후 앱을 안 열어도 대시보드에 온라인으로 뜨고, 원격 접속 시 화면/입력이 자동 동작해야 합니다."
