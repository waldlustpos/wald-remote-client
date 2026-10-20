// Waldlust(DSK-02 2단계 — 결정 D41): 도우미 → 원격 앱 상태 알림. 원격 앱이 IWaldInputBridge.registerCallback 으로 건넨다.
package co.kr.waldlust.remote.helper;

oneway interface IWaldInputCallback {
    void onInputStateChanged(boolean connected);
}
