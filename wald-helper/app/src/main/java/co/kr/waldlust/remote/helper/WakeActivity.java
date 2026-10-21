package co.kr.waldlust.remote.helper;

import android.app.Activity;
import android.os.Bundle;

/**
 * 메인 앱을 한 번 깨우고 화면 없이 바로 닫힌다. 도우미는 런처 아이콘이 없어(결정 D40) adb 로만 연다
 * (`am start -n co.kr.waldlust.remote.helper/.WakeActivity`). 열리면 도우미의 stopped 상태도 풀린다 — 메인 앱 1.5.4 이하처럼
 * 도우미를 활성화하지 못하는 경우의 대안이고, 화면 공유가 빠진 기기도 되살린다(메인 앱이 화면 공유를 다시 요청한다).
 * 메인 앱도 도우미가 stopped 면 이 화면을 연다(activate_only — 메인 앱은 이미 떠 있어 깨우지 않는다). MediaTek(IM-H092W)은 강제
 * 종료된 도우미를 방송·바인딩으로 띄우지 않고 화면을 열 때만 풀어 준다(부록 A-50 시험).
 */
public class WakeActivity extends Activity {
    static final String EXTRA_ACTIVATE_ONLY = "activate_only";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!getIntent().getBooleanExtra(EXTRA_ACTIVATE_ONLY, false)) {
            BootReceiver.wakeMain(this, "launch");
        }
        finish();
    }
}
