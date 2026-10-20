package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * Waldlust(DSK-02 2단계 — 부록 A-44, 결정 D41): 원격지원 도우미가 강제 종료된 이 앱을 되살릴 때 띄우는 투명한 화면.
 *
 * 도우미는 처음에 이 앱의 부팅 수신기(BootReceiver)로 깨우기 방송을 보냈는데, 일부 제조사 정책은 강제 종료된 앱의 프로세스를
 * 방송으로 띄우는 것을 막는다(IM-H092W MediaTek — 'suppress to start process of staticReceiver'). 접근성 서비스가 붙은 도우미는
 * 백그라운드에서도 화면을 띄울 수 있어(Android 백그라운드 화면 시작 예외) 이 화면으로 깨운다. 부팅 때와 같은 경로(BootReceiver —
 * '부팅 시 시작' 설정·권한 확인)로 서비스를 켜고 바로 닫힌다. 같은 서명 앱(도우미)만 열 수 있다(서명 권한 INPUT_BRIDGE).
 */
class WaldWakeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i("WaldWake", "woken by helper")
        BootReceiver().onReceive(this, Intent(DEBUG_BOOT_COMPLETED))
        finish()
        overridePendingTransition(0, 0)
    }
}
