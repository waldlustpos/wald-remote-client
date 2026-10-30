package com.carriez.flutter_hbb

/**
 * Handle events from flutter
 * Request MediaProjection permission
 *
 * Inspired by [droidVNC-NG] https://github.com/bk138/droidVNC-NG
 */

import ffi.FFI

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.ClipboardManager
import android.os.Bundle
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.WindowManager
import android.media.MediaFormat
import android.util.DisplayMetrics
import androidx.annotation.RequiresApi
import com.hjq.permissions.XXPermissions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread


class MainActivity : FlutterActivity() {
    companion object {
        var flutterMethodChannel: MethodChannel? = null
        private var _rdClipboardManager: RdClipboardManager? = null
        val rdClipboardManager: RdClipboardManager?
            get() = _rdClipboardManager;
    }

    private val channelTag = "mChannel"
    private val logTag = "mMainActivity"
    private var mainService: MainService? = null

    private var isAudioStart = false
    private val audioRecordHandle = AudioRecordHandle(this, { false }, { isAudioStart })

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (MainService.isReady) {
            Intent(activity, MainService::class.java).also {
                bindService(it, serviceConnection, Context.BIND_AUTO_CREATE)
            }
        }
        flutterMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelTag
        )
        initFlutterChannel(flutterMethodChannel!!)
        thread {
            try {
                setCodecInfo(this)
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to setCodecInfo: ${e.message}", e)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Waldlust(DSK-02 — 결정 D40): '출처를 알 수 없는 앱 설치'를 허용하고 돌아오면 도우미 설치를 이어 간다.
        WaldHelper.resumePendingInstall(this)
        // Waldlust(DSK-01 — 결정 D44): 앱 안 업데이트도 같다.
        WaldSelfUpdate.resumePendingInstall(this)
        val inputPer = WaldInputBridge.isInputOpen()
        activity.runOnUiThread {
            flutterMethodChannel?.invokeMethod(
                "on_state_changed",
                mapOf("name" to "input", "value" to inputPer.toString())
            )
        }
    }

    private fun requestMediaProjection() {
        val intent = Intent(this, PermissionRequestTransparentActivity::class.java).apply {
            action = ACT_REQUEST_MEDIA_PROJECTION
        }
        startActivityForResult(intent, REQ_INVOKE_PERMISSION_ACTIVITY_MEDIA_PROJECTION)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_INVOKE_PERMISSION_ACTIVITY_MEDIA_PROJECTION && resultCode == RES_FAILED) {
            flutterMethodChannel?.invokeMethod("on_media_projection_canceled", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (_rdClipboardManager == null) {
            _rdClipboardManager = RdClipboardManager(getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            FFI.setClipboardManager(_rdClipboardManager!!)
        }
        // Waldlust(DSK-12): 발신 전용(직원 폰)은 원격을 받지 않는다 — 아래 무인 운용 준비(권한 요청·입력 도우미)를 하지 않는다.
        if (BuildConfig.WALD_OUTGOING) return
        // Waldlust: 무인 키오스크는 재부팅 후에도 원격이 살아나야 한다.
        // "부팅 시 시작"을 기본 ON 으로 둔다(한 번도 설정된 적 없을 때만 → 운영자가 끈 경우는 존중).
        // 실제 부팅 자동시작은 BootReceiver 가 배터리최적화예외 + 오버레이 권한도 확인하므로,
        // 최초 설정 때 그 권한만 허용하면 이후 재부팅부터 자동으로 온라인이 된다.
        val bootPrefs = getSharedPreferences(KEY_SHARED_PREFERENCES, MODE_PRIVATE)
        if (!bootPrefs.contains(KEY_START_ON_BOOT_OPT)) {
            bootPrefs.edit().putBoolean(KEY_START_ON_BOOT_OPT, true).apply()
        }
        // Waldlust(무인): 부팅 자동시작이 실제로 동작하려면 배터리 최적화 예외 + 오버레이 권한이 필요하다.
        // BootReceiver 가 이 둘을 확인하고 없으면 자동시작을 건너뛰므로, 최초 실행 때 자동으로 요청한다.
        // (루팅이면 RootUtil 로도 부여되지만, 비루팅 기기는 이 1회 허용만으로 부팅 온라인이 된다.)
        // 미허용일 때만 요청 → 한 번 허용하면 재부팅해도 유지된다.
        try {
            val battery = android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
            val overlay = android.Manifest.permission.SYSTEM_ALERT_WINDOW
            if (!XXPermissions.isGranted(this, battery, overlay)) {
                XXPermissions.with(this)
                    .permission(battery)
                    .permission(overlay)
                    .request { _, _ -> }
            }
        } catch (e: Exception) {
            Log.w(logTag, "auto request unattended perms failed: ${e.message}")
        }
        // Waldlust(DSK-02): 강제 종료로 꺼진 접근성(입력)을 앱을 열 때 다시 켠다(adb 로 허용해 둔 기기만).
        RootUtil.enableInputServiceIfPermitted(this)
        // Waldlust(DSK-02 — 결정 D40): 아이콘 없는 도우미는 사람이 열 수 없으니 이 앱이 켜질 때 stopped 를 풀어 준다.
        WaldHelper.activateIfStopped(this)
        // 이 앱에 든 도우미가 더 새 버전이면 Android 12+ 는 창 없이 업데이트한다(그 밖은 홈 카드가 권한다).
        WaldHelper.updateSilentlyIfNeeded(this)
        // Waldlust(DSK-02 2단계 — 결정 D41): 도우미 입력 제어에 연결(adb 권한이 없어도)
        WaldInputBridge.ensureBound(this)
    }

    override fun onDestroy() {
        Log.e(logTag, "onDestroy")
        mainService?.let {
            unbindService(serviceConnection)
        }
        super.onDestroy()
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.d(logTag, "onServiceConnected")
            val binder = service as MainService.LocalBinder
            mainService = binder.getService()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(logTag, "onServiceDisconnected")
            mainService = null
        }
    }

    private fun initFlutterChannel(flutterMethodChannel: MethodChannel) {
        flutterMethodChannel.setMethodCallHandler { call, result ->
            // make sure result will be invoked, otherwise flutter will await forever
            when (call.method) {
                "init_service" -> {
                    Intent(activity, MainService::class.java).also {
                        bindService(it, serviceConnection, Context.BIND_AUTO_CREATE)
                    }
                    if (MainService.isReady) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    requestMediaProjection()
                    result.success(true)
                }
                "wald_auto_start_service" -> {
                    // Waldlust(DSK-02): 수신 전용은 앱을 열 때 서비스가 꺼져 있으면(강제 종료 뒤 등) 부팅 때와 같은 경로로 켠다.
                    // 설치자 1회 설정(배터리 최적화 예외·오버레이)이 끝난 기기만 — 첫 실행의 권한 요청과 겹치지 않게 한다.
                    val start = !MainService.isReady && XXPermissions.isGranted(
                        context,
                        android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        android.Manifest.permission.SYSTEM_ALERT_WINDOW
                    )
                    if (start) {
                        val serviceIntent = Intent(context, MainService::class.java).apply {
                            action = ACT_INIT_MEDIA_PROJECTION_AND_SERVICE
                            putExtra(EXT_INIT_FROM_BOOT, true)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                    }
                    result.success(start)
                }
                // Waldlust(DSK-02 — 결정 D40): 홈 '자동 복구' 카드 — 도우미 상태와 앱 안 설치 파일로 설치.
                "wald_helper_status" -> {
                    result.success(WaldHelper.status(this@MainActivity))
                }
                "wald_helper_install" -> {
                    result.success(WaldHelper.install(this@MainActivity))
                }
                // Waldlust(DSK-01 — 결정 D44): 수신 전용 앱 안 업데이트 — Rust 가 받아 확인한 APK 를 설치(WaldSelfUpdate.kt).
                "wald_self_update_install" -> {
                    result.success(WaldSelfUpdate.install(this@MainActivity, call.arguments as? String ?: ""))
                }
                // Waldlust(DSK-12): 받은 파일을 기본 앱으로 열기(WaldFiles.kt).
                "wald_open_file" -> {
                    result.success(WaldFiles.open(this@MainActivity, call.arguments as? String ?: ""))
                }
                "start_capture" -> {
                    mainService?.let {
                        result.success(it.startCapture())
                    } ?: let {
                        result.success(false)
                    }
                }
                "stop_service" -> {
                    Log.d(logTag, "Stop service")
                    mainService?.let {
                        it.destroy()
                        result.success(true)
                    } ?: let {
                        result.success(false)
                    }
                }
                "check_permission" -> {
                    if (call.arguments is String) {
                        result.success(XXPermissions.isGranted(context, call.arguments as String))
                    } else {
                        result.success(false)
                    }
                }
                "request_permission" -> {
                    if (call.arguments is String) {
                        requestPermission(context, call.arguments as String)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                START_ACTION -> {
                    if (call.arguments is String) {
                        startAction(context, call.arguments as String)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "check_video_permission" -> {
                    mainService?.let {
                        result.success(it.checkMediaPermission())
                    } ?: let {
                        result.success(false)
                    }
                }
                "check_service" -> {
                    Companion.flutterMethodChannel?.invokeMethod(
                        "on_state_changed",
                        mapOf("name" to "input", "value" to WaldInputBridge.isInputOpen().toString())
                    )
                    Companion.flutterMethodChannel?.invokeMethod(
                        "on_state_changed",
                        mapOf("name" to "media", "value" to MainService.isReady.toString())
                    )
                    result.success(true)
                }
                "stop_input" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        InputService.ctx?.disableSelf()
                    }
                    InputService.ctx = null
                    WaldInputBridge.disableInput() // Waldlust(DSK-02 2단계): 도우미 입력 제어도 끈다
                    Companion.flutterMethodChannel?.invokeMethod(
                        "on_state_changed",
                        mapOf("name" to "input", "value" to WaldInputBridge.isInputOpen().toString())
                    )
                    result.success(true)
                }
                "cancel_notification" -> {
                    if (call.arguments is Int) {
                        val id = call.arguments as Int
                        mainService?.cancelNotification(id)
                    } else {
                        result.success(true)
                    }
                }
                "enable_soft_keyboard" -> {
                    // https://blog.csdn.net/hanye2020/article/details/105553780
                    if (call.arguments as Boolean) {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
                    } else {
                        window.addFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
                    }
                    result.success(true)

                }
                "try_sync_clipboard" -> {
                    rdClipboardManager?.syncClipboard(true)
                    result.success(true)
                }
                GET_START_ON_BOOT_OPT -> {
                    val prefs = getSharedPreferences(KEY_SHARED_PREFERENCES, MODE_PRIVATE)
                    result.success(prefs.getBoolean(KEY_START_ON_BOOT_OPT, false))
                }
                SET_START_ON_BOOT_OPT -> {
                    if (call.arguments is Boolean) {
                        val prefs = getSharedPreferences(KEY_SHARED_PREFERENCES, MODE_PRIVATE)
                        val edit = prefs.edit()
                        edit.putBoolean(KEY_START_ON_BOOT_OPT, call.arguments as Boolean)
                        edit.apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                SYNC_APP_DIR_CONFIG_PATH -> {
                    if (call.arguments is String) {
                        val prefs = getSharedPreferences(KEY_SHARED_PREFERENCES, MODE_PRIVATE)
                        val edit = prefs.edit()
                        edit.putString(KEY_APP_DIR_CONFIG_PATH, call.arguments as String)
                        edit.apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                GET_VALUE -> {
                    if (call.arguments is String) {
                        if (call.arguments == KEY_IS_SUPPORT_VOICE_CALL) {
                            result.success(isSupportVoiceCall())
                        } else {
                            result.error("-1", "No such key", null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                "on_voice_call_started" -> {
                    onVoiceCallStarted()
                }
                "on_voice_call_closed" -> {
                    onVoiceCallClosed()
                }
                else -> {
                    result.error("-1", "No such method", null)
                }
            }
        }
    }

    private fun onVoiceCallStarted() {
        var ok = false
        mainService?.let {
            ok = it.onVoiceCallStarted()
        } ?: let {
            isAudioStart = true
            ok = audioRecordHandle.onVoiceCallStarted(null)
        }
        if (!ok) {
            // Rarely happens, So we just add log and msgbox here.
            Log.e(logTag, "onVoiceCallStarted fail")
            flutterMethodChannel?.invokeMethod("msgbox", mapOf(
                "type" to "custom-nook-nocancel-hasclose-error",
                "title" to "Voice call",
                "text" to "Failed to start voice call."))
        } else {
            Log.d(logTag, "onVoiceCallStarted success")
        }
    }

    private fun onVoiceCallClosed() {
        var ok = false
        mainService?.let {
            ok = it.onVoiceCallClosed()
        } ?: let {
            isAudioStart = false
            ok = audioRecordHandle.onVoiceCallClosed(null)
        }
        if (!ok) {
            // Rarely happens, So we just add log and msgbox here.
            Log.e(logTag, "onVoiceCallClosed fail")
            flutterMethodChannel?.invokeMethod("msgbox", mapOf(
                "type" to "custom-nook-nocancel-hasclose-error",
                "title" to "Voice call",
                "text" to "Failed to stop voice call."))
        } else {
            Log.d(logTag, "onVoiceCallClosed success")
        }
    }

    override fun onStop() {
        super.onStop()
        val disableFloatingWindow = FFI.getLocalOption("disable-floating-window") == "Y"
        if (!disableFloatingWindow && MainService.isReady) {
            startService(Intent(this, FloatingWindowService::class.java))
        }
    }

    override fun onStart() {
        super.onStart()
        stopService(Intent(this, FloatingWindowService::class.java))
    }
}
