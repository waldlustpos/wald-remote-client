package co.kr.waldlust.remote.helper

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * 원격 앱이 강제 종료되거나 죽으면 몇 초 뒤 다시 깨운다(부록 A-44 2단계, 결정 D41 — 사용자 결정 '자동 되살림').
 *
 * 도우미 접근성은 시스템이 계속 붙들고 있어 이 프로세스가 살아 있다. 원격 앱 프로세스가 죽으면 입력 브리지 콜백이 끊기고
 * (InputBridgeService.onCallbackDied), 강제 종료면 시스템 방송 ACTION_PACKAGE_RESTARTED 도 온다. 그때 부팅 때와 같은 깨우기
 * 신호(BootReceiver.wakeMain)를 보내면 원격 앱이 서비스·화면 공유를 다시 켜고, 이 도우미가 동의 창을 자동 승인한다.
 *
 * 되살리는 조건(모두): 원격 앱이 서비스를 켜 둔 상태였다(사용자가 서비스를 멈춘 뒤가 아님), 도우미 접근성이 켜져 있다(아니면
 * 무인 화면에 동의 창만 뜬다), 원격 앱이 설치돼 있고 데이터를 지운 직후가 아니다, 3초 안에 원격 앱이 스스로 다시 붙지 않았다,
 * 10분에 3번을 넘지 않았다(켜자마자 죽는 고리 방지). 원격 앱 쪽 부팅 수신기가 '부팅 시 시작' 설정·권한을 다시 확인한다.
 */
object MainWatcher {
    private const val TAG = "WaldHelperWatch"
    private const val MAIN_PKG = InputBridgeService.MAIN_PKG
    private const val REVIVE_DELAY_MS = 3_000L
    private const val WINDOW_MS = 10 * 60_000L
    private const val MAX_REVIVES = 3
    private const val PREFS = "wald_main_watcher"
    private const val KEY_REVIVES = "revives"
    // 원격 앱 깨우기 화면(applicationId 와 Kotlin 네임스페이스가 달라 클래스는 전체 이름 — 결정 D35)
    private const val MAIN_WAKE_ACTIVITY = "com.carriez.flutter_hbb.WaldWakeActivity"

    private val handler = Handler(Looper.getMainLooper())
    @Volatile
    private var pending = false
    @Volatile
    private var dataCleared = false
    private var appContext: Context? = null
    private var receiverRegistered = false

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.data?.schemeSpecificPart != MAIN_PKG) return
            when (intent.action) {
                Intent.ACTION_PACKAGE_RESTARTED -> onMainDied("force-stop")
                Intent.ACTION_PACKAGE_DATA_CLEARED -> {
                    // 데이터를 지우면 새 기기 ID 가 된다 — 되살리지 않고 사람이 다시 설정하게 둔다.
                    Log.i(TAG, "main app data cleared — not reviving")
                    dataCleared = true
                    InputBridgeService.mainServiceRunning = false
                }
            }
        }
    }

    /** 도우미 접근성이 연결되면 원격 앱 강제 종료 방송을 듣기 시작한다(InputService.onServiceConnected). */
    @Synchronized
    fun start(context: Context) {
        val app = context.applicationContext
        appContext = app
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_RESTARTED)
            addAction(Intent.ACTION_PACKAGE_DATA_CLEARED)
            addDataScheme("package")
        }
        // 시스템 방송만 받는다. targetSdk 34+ 는 내보내기 여부를 밝혀야 한다 — 시스템 방송은 NOT_EXPORTED 로도 받는다.
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            app.registerReceiver(packageReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            app.registerReceiver(packageReceiver, filter)
        }
        receiverRegistered = true
    }

    /** 원격 앱 프로세스가 죽었다(입력 브리지 콜백 끊김 또는 강제 종료 방송). */
    fun onMainDied(why: String) {
        if (!InputBridgeService.mainServiceRunning) {
            Log.i(TAG, "main died ($why) — service was not running, not reviving")
            return
        }
        if (!InputService.isOpen) {
            Log.i(TAG, "main died ($why) — helper input is off, not reviving")
            return
        }
        if (pending) return
        pending = true
        Log.i(TAG, "main died ($why) — revive in ${REVIVE_DELAY_MS}ms")
        handler.postDelayed({ revive(why) }, REVIVE_DELAY_MS)
    }

    /** 원격 앱이 다시 붙었다(사람이 앱을 열었거나 스스로 다시 켜짐) — 예약한 되살리기를 취소한다. */
    fun onMainRegistered() {
        dataCleared = false
        if (pending) {
            pending = false
            handler.removeCallbacksAndMessages(null)
            Log.i(TAG, "main app is back — revive cancelled")
        }
    }

    private fun revive(why: String) {
        pending = false
        val ctx = appContext ?: return
        if (dataCleared || !InputBridgeService.mainServiceRunning) {
            Log.i(TAG, "revive skipped (dataCleared=$dataCleared)")
            return
        }
        try {
            ctx.packageManager.getApplicationInfo(MAIN_PKG, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            Log.i(TAG, "main app not installed — not reviving")
            return
        }
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val recent = (prefs.getString(KEY_REVIVES, "") ?: "").split(',')
            .mapNotNull { it.toLongOrNull() }
            .filter { now - it in 0 until WINDOW_MS }
        if (recent.size >= MAX_REVIVES) {
            Log.w(TAG, "revive limit reached (${recent.size} in 10 min) — not reviving")
            return
        }
        prefs.edit().putString(KEY_REVIVES, (recent + now).joinToString(",")).apply()
        // 원격 앱의 투명 깨우기 화면으로 깨운다. 일부 제조사는 강제 종료된 앱을 방송으로 띄우는 것을 막는다(IM-H092W MediaTek —
        // 'suppress to start process of staticReceiver'). 접근성이 붙은 이 앱은 백그라운드에서도 화면을 띄울 수 있다.
        // 깨우기 화면이 없는 옛 원격 앱이면 부팅 때와 같은 방송으로.
        val wake = Intent().apply {
            component = ComponentName(MAIN_PKG, MAIN_WAKE_ACTIVITY)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        }
        try {
            (InputService.ctx ?: ctx).startActivity(wake)
            Log.i(TAG, "woke main app via wake activity (revive after $why)")
        } catch (e: Exception) {
            Log.i(TAG, "wake activity failed ($e) — broadcast instead")
            BootReceiver.wakeMain(ctx, "revive after $why")
        }
    }
}
