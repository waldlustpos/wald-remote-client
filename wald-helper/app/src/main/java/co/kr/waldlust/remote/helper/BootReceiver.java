package co.kr.waldlust.remote.helper;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.util.Log;

/**
 * Waldlust 원격지원 도우미(부록 A-44 1단계).
 *
 * 메인 앱(co.kr.waldlust.remote)을 앱 정보에서 강제 종료하면 Android 가 그 패키지를 stopped 로 두고,
 * stopped 패키지는 재부팅해도 BOOT_COMPLETED 를 받지 못해 누가 앱을 열 때까지 오프라인이다.
 * 이 도우미는 따로인 패키지라 메인 앱 강제 종료와 상관없이 부팅 신호를 받고, 메인 앱이 stopped 면
 * 메인 앱의 부팅 수신기를 명시적으로(FLAG_INCLUDE_STOPPED_PACKAGES) 불러 깨운다. 깨어난 메인 앱은
 * 부팅 때와 같은 경로로 서비스·접근성(adb 로 WRITE_SECURE_SETTINGS 를 허용한 기기)·화면 공유를 되살린다.
 */
public class BootReceiver extends BroadcastReceiver {
    static final String TAG = "WaldHelper";
    static final String MAIN_PKG = "co.kr.waldlust.remote";
    // 메인 앱의 부팅 수신기(applicationId 와 Kotlin 네임스페이스가 달라 클래스는 전체 이름 — 결정 D35)
    static final String MAIN_BOOT_RECEIVER = "com.carriez.flutter_hbb.BootReceiver";
    static final String MAIN_WAKE_ACTION = "com.carriez.flutter_hbb.DEBUG_BOOT_COMPLETED";
    // 메인 앱(1.5.5+)이 켜질 때 보낸다. 이 신호가 전달되는 것만으로 Android 가 이 앱의 stopped 상태를 푼다(아이콘이 없어
    // 사람이 한 번 열 수 없다 — 결정 D40). 메인 앱을 다시 깨우지는 않는다(서로 부르는 고리가 생기지 않게).
    static final String ACTION_ACTIVATE = "co.kr.waldlust.remote.helper.ACTIVATE";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (ACTION_ACTIVATE.equals(action)) {
            Log.d(TAG, "activated by main app");
            return;
        }
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !"android.intent.action.QUICKBOOT_POWERON".equals(action)) {
            return;
        }
        // 메인 앱이 stopped 가 아니면 자기 부팅 수신기로 스스로 뜬다 — 두 번 깨우지 않는다.
        if (!isMainStopped(context)) {
            Log.d(TAG, "boot: main app not stopped, it starts by itself");
            return;
        }
        wakeMain(context, "boot");
    }

    static boolean isMainStopped(Context context) {
        try {
            ApplicationInfo info = context.getPackageManager().getApplicationInfo(MAIN_PKG, 0);
            return (info.flags & ApplicationInfo.FLAG_STOPPED) != 0;
        } catch (PackageManager.NameNotFoundException e) {
            Log.w(TAG, "main app not installed");
            return false;
        }
    }

    static void wakeMain(Context context, String why) {
        Intent wake = new Intent(MAIN_WAKE_ACTION);
        wake.setComponent(new ComponentName(MAIN_PKG, MAIN_BOOT_RECEIVER));
        wake.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
        // 부팅 때는 백그라운드 방송 대기열이 앱 전체의 BOOT_COMPLETED 를 차례로 돌리느라 막혀 있어
        // 그냥 보내면 메인 앱이 70초 뒤에 받았다(RK3568) → 포그라운드 대기열로 보낸다.
        wake.addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
        context.sendBroadcast(wake);
        Log.d(TAG, "woke main app (" + why + ")");
    }
}
