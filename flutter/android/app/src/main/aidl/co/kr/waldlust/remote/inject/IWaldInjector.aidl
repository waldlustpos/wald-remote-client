// Waldlust(DSK-02 — 부록 A-69, 결정 D47): 원격 앱 → 입력 주입 플러그인.
// 플러그인(co.kr.waldlust.remote.inject — 보드 플랫폼 키로 서명해 INJECT_EVENTS 를 받는다)의 InjectService 가 구현하고,
// 원격 앱(WaldInjector.kt)이 바인딩해 쓴다. 이 파일이 정본이다 — 플러그인 빌드(wald-inject/app/build.gradle)가 이 폴더를 그대로 읽는다.
// 규칙: 메서드는 끝에만 덧붙인다(트랜잭션 번호 = 선언 순서). 새 메서드를 쓰기 전에 protocolVersion() 을 확인한다.
package co.kr.waldlust.remote.inject;

interface IWaldInjector {
    // 1
    int protocolVersion();
    // 이 기기에서 INJECT_EVENTS 가 허가됐는가(플러그인이 이 기기 플랫폼 키로 서명됐는가)
    boolean canInject();
    // 원격 앱 프로세스 표식 — 원격 앱이 죽으면 플러그인이 진행 중인 획을 취소한다.
    void attach(IBinder token);
    // kind 0 = touch, 1 = mouse. mask 는 도우미 InputService 와 같다. x·y 는 원격 앱이 SCREEN_INFO.scale 을 곱한 값이다.
    oneway void pointer(int kind, int mask, int x, int y);
}
