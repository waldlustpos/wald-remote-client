package co.kr.waldlust.remote.helper;

import android.app.Activity;
import android.os.Bundle;

/**
 * 메인 앱을 한 번 깨우고 화면 없이 바로 닫힌다. 도우미는 런처 아이콘이 없어(결정 D40) adb 로만 연다
 * (`am start -n co.kr.waldlust.remote.helper/.WakeActivity`). 열리면 도우미의 stopped 상태도 풀린다 — 메인 앱 1.5.4 이하처럼
 * 도우미를 활성화하지 못하는 경우의 대안이고, 화면 공유가 빠진 기기도 되살린다(메인 앱이 화면 공유를 다시 요청한다).
 */
public class WakeActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        BootReceiver.wakeMain(this, "launch");
        finish();
    }
}
