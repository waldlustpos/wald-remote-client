package co.kr.waldlust.remote.helper;

import android.app.Activity;
import android.os.Bundle;

/**
 * 설치 뒤 한 번 실행해 도우미의 stopped 상태를 푼다(새로 설치한 앱은 한 번 실행하기 전에는 부팅 신호를 받지 못한다).
 * 실행하면 메인 앱도 한 번 깨우고 화면 없이 바로 닫힌다.
 */
public class WakeActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        BootReceiver.wakeMain(this, "launch");
        finish();
    }
}
