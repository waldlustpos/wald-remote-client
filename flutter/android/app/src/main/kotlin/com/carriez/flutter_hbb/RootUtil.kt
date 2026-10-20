package com.carriez.flutter_hbb

import android.Manifest.permission.WRITE_SECURE_SETTINGS
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Waldlust: 루팅된 무인 키오스크에서 "켜면 자동으로 원격이 되는" 것을 위한 root 헬퍼.
 *
 * 표준 안드로이드는 (1) 화면공유(MediaProjection) 동의 팝업, (2) 접근성(입력) 수동 활성화 때문에
 * 무인 동작이 막힌다. 제어 가능한(루팅된) 박스에서는 su 로 접근성을 자동 활성화하고,
 * 화면공유 팝업은 접근성 서비스가 자동 클릭하도록 하여 사람 손 없이 동작하게 한다.
 *
 * 모든 호출은 실패해도 조용히 넘어간다(루트 없음/명령 실패 시 기존 수동 흐름으로 폴백).
 */
object RootUtil {
    private const val logTag = "WaldRoot"

    /** su 로 한 줄 명령 실행. 성공 시 stdout, 실패/루트없음 시 null. */
    fun runAsRoot(cmd: String): String? {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", cmd))
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            val code = p.waitFor()
            if (code != 0) {
                Log.w(logTag, "root cmd rc=$code cmd=$cmd err=${err.trim()}")
            }
            out
        } catch (e: Exception) {
            Log.w(logTag, "root unavailable or cmd failed: $cmd (${e.message})")
            null
        }
    }

    /**
     * Waldlust(DSK-02): root 없이 접근성(입력)을 켠다. 앱을 강제 종료하면 시스템이 접근성 목록에서 이 앱을 지우므로
     * 앱을 열 때·화면공유를 요청할 때 다시 켠다. 설치자가 adb 로 한 번 허용해 둔 기기에서만 된다:
     * `adb shell pm grant <패키지> android.permission.WRITE_SECURE_SETTINGS`(앱을 지우기 전까지 유지).
     * 권한이 없으면 아무것도 하지 않는다(설치자 수동 활성화 그대로). 켰으면(이미 켜져 있었으면) true.
     */
    fun enableInputServiceIfPermitted(context: Context): Boolean {
        if (ContextCompat.checkSelfPermission(context, WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        if (InputService.isOpen) return true
        val now = SystemClock.elapsedRealtime()
        if (now - lastEnableMs < 3_000L) return true // 앱 시작·서비스 시작이 겹쳐 불려도 한 번만
        lastEnableMs = now
        val app = context.applicationContext
        if (!putInputServiceEnabled(app, true)) return false
        // Android 11 은 강제 종료된 접근성 서비스를 '충돌'로 기록해 목록에 다시 넣어도 바인드하지 않는다(D2s).
        // 곧 연결되지 않으면 목록에서 뺐다가 다시 넣어 그 기록을 지운다.
        val handler = Handler(Looper.getMainLooper())
        handler.postDelayed({
            if (!InputService.isOpen) {
                Log.d(logTag, "accessibility not bound, toggling off and on")
                putInputServiceEnabled(app, false)
                handler.postDelayed({ putInputServiceEnabled(app, true) }, 500)
            }
        }, 1_500)
        return true
    }

    @Volatile
    private var lastEnableMs = 0L

    private fun putInputServiceEnabled(context: Context, enabled: Boolean): Boolean {
        return try {
            val service = ComponentName(context, InputService::class.java).flattenToString()
            val resolver = context.contentResolver
            val current = Settings.Secure.getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
            val others = current.split(':').filter { it.isNotBlank() && !it.equals(service, ignoreCase = true) }
            val merged = (if (enabled) others + service else others).joinToString(":")
            if (merged != current) {
                Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, merged)
                Log.d(logTag, "accessibility ${if (enabled) "re-enabled" else "disabled"} via WRITE_SECURE_SETTINGS")
            }
            if (enabled) Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            true
        } catch (e: Exception) {
            Log.w(logTag, "set accessibility failed: ${e.message}")
            false
        }
    }

    fun isRootAvailable(): Boolean {
        val out = runAsRoot("id") ?: return false
        return out.contains("uid=0")
    }

    /**
     * 무인 동작에 필요한 표준 권한/설정을 root 로 한 번에 확정한다.
     *  - 접근성 InputService 활성화(입력)
     *  - 배터리 최적화 화이트리스트(부팅/백그라운드 유지)
     *  - 다른 앱 위에 표시(SYSTEM_ALERT_WINDOW) — BootReceiver 통과 조건
     * 이미 되어 있으면 무해하게 통과. 부팅 시/서비스 시작 시 호출한다.
     */
    fun ensureUnattendedGrants(pkg: String) {
        // 접근성(입력) 활성화
        // applicationId(co.kr.waldlust.remote)와 Kotlin 네임스페이스가 달라 클래스 이름은 전체 이름으로 적는다(Q-29, D35).
        val service = "$pkg/com.carriez.flutter_hbb.InputService"
        val current = runAsRoot("settings get secure enabled_accessibility_services")?.trim() ?: ""
        if (!current.contains(service)) {
            val merged = if (current.isBlank() || current == "null") service else "$current:$service"
            runAsRoot("settings put secure enabled_accessibility_services '$merged'")
        }
        runAsRoot("settings put secure accessibility_enabled 1")

        // 배터리 최적화 예외(도즈 화이트리스트)
        runAsRoot("dumpsys deviceidle whitelist +$pkg")

        // 다른 앱 위에 표시(오버레이) 허용 — BootReceiver 의 SYSTEM_ALERT_WINDOW 조건 통과용
        runAsRoot("appops set $pkg SYSTEM_ALERT_WINDOW allow")
    }
}
