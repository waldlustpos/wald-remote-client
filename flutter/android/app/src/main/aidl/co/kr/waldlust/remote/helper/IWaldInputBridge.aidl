// Waldlust(DSK-02 2단계 — 결정 D41): 원격 앱 → 원격지원 도우미 입력 브리지.
// 도우미(co.kr.waldlust.remote.helper)의 InputBridgeService 가 구현하고, 원격 앱(WaldInputBridge.kt)이 바인딩해 쓴다.
// 이 파일이 정본이다 — 도우미 빌드(wald-helper/app/build.gradle)가 이 폴더를 그대로 읽는다.
// 규칙: 메서드는 끝에만 덧붙인다(트랜잭션 번호 = 선언 순서). 새 메서드를 쓰기 전에 protocolVersion() 을 확인한다.
package co.kr.waldlust.remote.helper;

import android.view.KeyEvent;
import co.kr.waldlust.remote.helper.IWaldInputCallback;

interface IWaldInputBridge {
    // 1
    int protocolVersion();
    // 도우미의 접근성(입력 제어) 서비스가 연결돼 있는가
    boolean isInputConnected();
    void registerCallback(IWaldInputCallback cb);
    void unregisterCallback(IWaldInputCallback cb);
    // kind 0 = touch, 1 = mouse. x·y 는 원격 앱이 SCREEN_INFO.scale 을 곱한 화면 픽셀이다.
    oneway void pointer(int kind, int mask, int x, int y);
    // 원격 앱이 protobuf KeyEvent 를 풀어 넘긴다. event 는 API 33+ 이고 text 가 있으면 null 이다. press = 누르고 떼기 한 번.
    oneway void key(in KeyEvent event, String text, boolean press);
    // 허용 목록만 수행한다(지금은 GLOBAL_ACTION_POWER_DIALOG).
    oneway void globalAction(int action);
    // 화면 공유 동의 창 자동 승인을 durationMs 동안 켠다.
    oneway void armProjectionAccept(long durationMs);
    // 도우미 접근성을 끈다(입력 제어 끄기).
    oneway void disableInput();
    // 원격 앱 서비스가 켜졌는지(도우미가 원격 앱을 되살릴지 판단할 때 쓴다).
    oneway void setMainServiceRunning(boolean running);
}
