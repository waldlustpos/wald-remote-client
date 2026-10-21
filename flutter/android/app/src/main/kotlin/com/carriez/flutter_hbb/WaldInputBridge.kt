package com.carriez.flutter_hbb

import android.Manifest.permission.WRITE_SECURE_SETTINGS
import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.RemoteException
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent as KeyEventAndroid
import androidx.core.content.ContextCompat
import co.kr.waldlust.remote.helper.IWaldInputBridge
import co.kr.waldlust.remote.helper.IWaldInputCallback
import hbb.KeyEventConverter
import hbb.MessageOuterClass.KeyEvent
import hbb.MessageOuterClass.KeyboardMode

/**
 * Waldlust(DSK-02 2단계 — 부록 A-44, 결정 D41): 원격지원 도우미의 입력 제어(접근성)로 원격 입력을 보낸다.
 *
 * 앱을 강제 종료하면 시스템이 이 앱의 접근성(InputService)을 목록에서 지운다. 도우미(co.kr.waldlust.remote.helper)의 접근성은
 * 패키지가 달라 그대로 남으므로(AnyDesk 플러그인 ad1 과 같은 구조) 도우미 접근성이 켜져 있으면 그쪽으로 입력을 보낸다.
 * - 도우미에 입력 기능이 있고(INPUT_BRIDGE 서비스) 이 앱과 같은 서명일 때만 쓴다(가짜 도우미·r3·1.5.5 이전 도우미 제외).
 * - 상태: LEGACY(도우미 안 씀 — 이 앱 InputService 그대로) → BINDING → BOUND. BOUND 에서 도우미 접근성이 연결돼 있으면 ready.
 * - ready 면 입력은 도우미로, 아니면 이 앱 InputService 로(지금과 같다). 양방향 빌드는 도우미가 없어 늘 LEGACY.
 * - adb 권한(WRITE_SECURE_SETTINGS)이 있으면 도우미 접근성을 켜고, 켜지면 이 앱 접근성을 목록에서 뺀다(자동 이전 — RootUtil).
 * - 도우미 접근성이 연결되면 이 앱 InputService 구성요소를 꺼서 접근성 설정 화면에 도우미 한 줄만 보이게 한다(AnyDesk ad1 처럼
 *   — 부록 A-50). 도우미가 없어지거나 도우미 접근성이 설정에서 꺼지면 다시 켠다(updateMainInputVisibility).
 * 입력한 글자는 로그에 남기지 않는다.
 */
object WaldInputBridge {
    private const val logTag = "WaldInputBridge"
    private const val ACTION_INPUT_BRIDGE = "co.kr.waldlust.remote.helper.INPUT_BRIDGE"
    private const val REQUIRED_PROTOCOL = 1
    val HELPER_INPUT_SERVICE = ComponentName(WaldHelper.PKG, "co.kr.waldlust.remote.helper.InputService")

    private enum class State { LEGACY, BINDING, BOUND }

    @Volatile
    private var state = State.LEGACY
    @Volatile
    private var remote: IWaldInputBridge? = null
    // 도우미 접근성이 연결돼 있다(도우미가 알려 온 값).
    @Volatile
    private var ready = false
    @Volatile
    private var appContext: Context? = null
    // 화면 공유 자동 승인을 켜 둘 만료 시각 — 도우미 연결 전에 요청되면 연결될 때 남은 시간으로 보낸다.
    @Volatile
    private var armUntil = 0L
    // adb 권한이 있어 도우미 접근성을 켜야 하는데 아직 연결 전이다 — 연결되면 켠다.
    @Volatile
    private var pendingEnable = false
    // 원격 서비스가 켜져 있다 — 도우미는 이 값이 true 일 때 이 앱이 죽으면 다시 깨운다(MainWatcher).
    @Volatile
    private var mainServiceRunning = false

    private var bound = false
    private var bindCheckToken = 0 // 죽은 바인딩 확인용(scheduleBindCheck)
    private var receiverRegistered = false
    private var retryDelayMs = 1_000L
    private val mainHandler = Handler(Looper.getMainLooper())

    private val volumeController: VolumeController? by lazy {
        (appContext?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.let { VolumeController(it) }
    }

    /** 도우미에 입력 기능이 있고 같은 서명이면 도우미 접근성 컴포넌트, 아니면 null. */
    fun helperInputComponent(context: Context): ComponentName? {
        val pm = context.packageManager
        if (pm.resolveService(Intent(ACTION_INPUT_BRIDGE).setPackage(WaldHelper.PKG), 0) == null) return null
        if (pm.checkSignatures(context.packageName, WaldHelper.PKG) != PackageManager.SIGNATURE_MATCH) {
            Log.w(logTag, "helper signature mismatch — not used")
            return null
        }
        return HELPER_INPUT_SERVICE
    }

    /** 도우미 브리지에 바인딩한다(한 번만 — 프로세스가 사는 동안 유지). 도우미 설치·업데이트·삭제도 지켜본다. */
    @Synchronized
    fun ensureBound(context: Context) {
        val app = context.applicationContext
        appContext = app
        if (!receiverRegistered) {
            // 시스템 방송만 받는다(targetSdk 33 — 내보내기 플래그 불필요).
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_PACKAGE_ADDED)
                addAction(Intent.ACTION_PACKAGE_REPLACED)
                addAction(Intent.ACTION_PACKAGE_REMOVED)
                addDataScheme("package")
            }
            app.registerReceiver(packageReceiver, filter)
            receiverRegistered = true
        }
        if (bound) return
        if (helperInputComponent(app) == null) {
            state = State.LEGACY
            setMainInputHidden(app, false) // 이 앱이 꺼져 있는 동안 도우미가 지워졌을 수 있다
            return
        }
        val intent = Intent(ACTION_INPUT_BRIDGE).setPackage(WaldHelper.PKG)
        bound = try {
            app.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        } catch (e: SecurityException) {
            Log.w(logTag, "bind refused: ${e.message}")
            false
        }
        if (bound) {
            state = State.BINDING
            Log.d(logTag, "binding helper bridge")
            scheduleBindCheck(10_000L)
        } else {
            state = State.LEGACY
            unbindQuietly(app)
            setMainInputHidden(app, false)
            // 도우미 프로세스를 띄우지 못하면(제조사 정책 — IM-H092W 'process is bad') 바인딩이 바로 거절된다. 조금 뒤 다시 한다.
            Log.i(logTag, "helper bridge bind failed, retry in ${retryDelayMs}ms")
            mainHandler.removeCallbacks(retryBind) // 여러 곳에서 불려도 기다리는 재시도는 하나만
            mainHandler.postDelayed(retryBind, retryDelayMs)
            retryDelayMs = (retryDelayMs * 2).coerceAtMost(60_000L)
        }
    }

    @Synchronized
    private fun unbind() {
        val app = appContext ?: return
        if (bound) unbindQuietly(app)
        bound = false
        remote = null
        ready = false
        state = State.LEGACY
    }

    private fun unbindQuietly(app: Context) {
        try {
            app.unbindService(connection)
        } catch (e: IllegalArgumentException) {
            // 바인딩되지 않은 연결
        }
    }

    private fun rebindLater(delayMs: Long) {
        mainHandler.postDelayed({ appContext?.let { ensureBound(it) } }, delayMs)
    }

    private val retryBind = Runnable { appContext?.let { ensureBound(it) } }

    /** 바인딩이 죽었다 — 풀고 조금 뒤 다시 바인딩한다. */
    private fun rebindAfterDeath() {
        Log.i(logTag, "helper binding died, rebind in ${retryDelayMs}ms")
        unbind()
        onStateChanged()
        rebindLater(retryDelayMs)
        retryDelayMs = (retryDelayMs * 2).coerceAtMost(60_000L)
    }

    /**
     * delayMs 안에 브리지가 연결되지 않으면 죽은 것으로 보고 다시 바인딩한다(부록 A-50 시험). 콜백이 오지 않는 두 경우:
     * - 도우미 프로세스를 띄우지 못한 바인딩 — 제조사 정책(IM-H092W MediaTek 'process is bad')이 막으면 그대로 BINDING 에 머문다.
     * - Android 7 이하 강제 종료(onBindingDied 없음 — T2 mini).
     */
    private fun scheduleBindCheck(delayMs: Long) {
        val token = ++bindCheckToken
        mainHandler.postDelayed({
            if (token == bindCheckToken && bound && remote == null && state == State.BINDING) rebindAfterDeath()
        }, delayMs)
    }

    /** 원격 앱이 도우미를 화면으로 깨웠다(WaldHelper.activateIfStopped) — 막혀 있던 동안 실패한 바인딩을 곧 다시 한다. */
    fun onHelperActivated(context: Context) {
        val app = context.applicationContext
        mainHandler.postDelayed({
            if (bound && remote == null) {
                retryDelayMs = 1_000L
                rebindAfterDeath()
            }
            // 시스템도 도우미 접근성 연결을 다시 시도하게 한다(접근성 목록 다시 읽기).
            if (isHelperListedInSettings(app)) refreshA11yList(app)
        }, 1_500L)
    }

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.data?.schemeSpecificPart != WaldHelper.PKG) return
            val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
            Log.d(logTag, "helper package ${intent.action} replacing=$replacing")
            if (intent.action == Intent.ACTION_PACKAGE_REMOVED && replacing) return // 업데이트 — 뒤따르는 REPLACED 에서
            unbind()
            onStateChanged()
            if (intent.action == Intent.ACTION_PACKAGE_REMOVED) {
                // 도우미가 지워졌다 — adb 권한이 있으면 이 앱 접근성을 다시 켠다.
                RootUtil.enableInputServiceIfPermitted(context)
            } else {
                rebindLater(500)
            }
        }
    }

    private val callback = object : IWaldInputCallback.Stub() {
        override fun onInputStateChanged(connected: Boolean) {
            val app = appContext ?: return
            if (app.packageManager.getPackagesForUid(Binder.getCallingUid())?.contains(WaldHelper.PKG) != true) return
            mainHandler.post {
                ready = connected && remote != null
                Log.i(logTag, "helper input ${if (ready) "connected" else "disconnected"}")
                onStateChanged()
            }
        }
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val r = IWaldInputBridge.Stub.asInterface(service)
            try {
                if (r == null || r.protocolVersion() < REQUIRED_PROTOCOL) {
                    Log.w(logTag, "helper bridge protocol too old")
                    unbind()
                    onStateChanged()
                    return
                }
                r.registerCallback(callback)
                remote = r
                state = State.BOUND
                retryDelayMs = 1_000L
                ready = r.isInputConnected()
                val left = armUntil - SystemClock.uptimeMillis()
                if (left > 0) r.armProjectionAccept(left)
                r.setMainServiceRunning(mainServiceRunning)
            } catch (e: Exception) {
                // RemoteException·SecurityException(서명이 다른 도우미)
                Log.w(logTag, "helper bridge setup failed: $e")
                remote = null
                ready = false
            }
            Log.i(logTag, "helper bridge connected, input=$ready")
            if (pendingEnable && !ready) {
                pendingEnable = false
                appContext?.let { enableHelperNow(it) }
            }
            onStateChanged()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            // 도우미 프로세스가 죽었다 — 바인딩은 남아 있어 시스템이 다시 띄우면 onServiceConnected 가 다시 온다.
            Log.i(logTag, "helper bridge disconnected")
            remote = null
            ready = false
            state = State.BINDING
            onStateChanged()
            // Android 7 이하는 onBindingDied 가 없다 — 도우미가 강제 종료되면 바인딩이 죽은 채(DEAD) 다시 오지 않는다(T2 mini 7.1).
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) scheduleBindCheck(5_000L)
        }

        override fun onBindingDied(name: ComponentName?) {
            // 도우미 업데이트·강제 종료 — 다시 바인딩한다(바인딩하면 도우미 stopped 도 풀린다).
            rebindAfterDeath()
        }

        override fun onNullBinding(name: ComponentName?) {
            unbind()
        }
    }

    private fun markDead(e: RemoteException) {
        Log.w(logTag, "helper bridge call failed: $e")
        remote = null
        ready = false
        mainHandler.post { onStateChanged() }
    }

    /** 입력 제어 상태가 바뀌었다 — Flutter(입력 제어 토글·enable-keyboard)와 홈 카드에 알리고, adb 권한이 있으면 이 앱 접근성을 정리한다. */
    private fun onStateChanged() {
        val open = isInputOpen()
        MainActivity.flutterMethodChannel?.invokeMethod(
            "on_state_changed",
            mapOf("name" to "input", "value" to open.toString())
        )
        WaldHelper.notifyFlutter("input")
        val app = appContext ?: return
        if (ready && ContextCompat.checkSelfPermission(app, WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED) {
            // 도우미 접근성이 켜졌다 — 이 앱 것은 목록에서 뺀다(입력이 한 경로로만, 설정 화면에 '켜짐'이 둘 보이지 않게).
            // 도우미가 지워지면 RootUtil 이 이 앱 것을 다시 넣는다.
            RootUtil.putInputServiceEnabled(app, false)
        }
        updateMainInputVisibility(app)
    }

    /** 이 앱 접근성(InputService)을 접근성 설정 화면에 보일지 정한다(부록 A-50). */
    private fun updateMainInputVisibility(app: Context) {
        when {
            ready -> setMainInputHidden(app, true)
            helperInputComponent(app) == null -> setMainInputHidden(app, false)
            // 도우미 접근성이 설정에서 꺼졌다(사용자·입력 제어 끄기·도우미 강제 종료) — 어느 쪽이든 다시 켤 수 있게
            state == State.BOUND && !isHelperListedInSettings(app) -> setMainInputHidden(app, false)
            // 그 밖(연결 중·도우미 프로세스 재시작·업데이트 — 설정에는 켜져 있다)은 그대로 둔다(숨겼다 보였다 하지 않게).
        }
    }

    /** 이 앱 InputService 구성요소를 끄거나(설정 목록에서 사라지고, 연결돼 있었으면 시스템이 끊는다) 매니페스트 기본값(켜짐)으로 되돌린다. */
    fun setMainInputHidden(context: Context, hidden: Boolean) {
        val pm = context.packageManager
        val component = ComponentName(context, InputService::class.java)
        val wanted = if (hidden) PackageManager.COMPONENT_ENABLED_STATE_DISABLED else PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
        try {
            if (pm.getComponentEnabledSetting(component) == wanted) return
            if (hidden && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // 연결된 채로 구성요소를 끄면 시스템이 '오작동(crashed)'으로 기록해 되살려도 다시 연결되지 않는다
                // (에뮬레이터 API 34 확인) — 먼저 스스로 접근성 목록에서 빠진다(권한 필요 없음).
                InputService.ctx?.disableSelf()
            }
            pm.setComponentEnabledSetting(component, wanted, PackageManager.DONT_KILL_APP)
            refreshA11yList(context)
            Log.i(logTag, "main InputService ${if (hidden) "hidden" else "shown"}")
        } catch (e: Exception) {
            Log.w(logTag, "set main InputService state failed: ${e.message}")
        }
    }

    /**
     * 시스템 접근성 목록을 바로 다시 읽게 한다. 시스템은 구성요소 하나가 바뀐 것으로는 다시 읽지 않는다(앱 설치·업데이트·삭제·재부팅
     * 때만 — 에뮬레이터 API 34). 패키지 이름과 같은 이름의 구성요소(manifest activity-alias)를 바꾸면(켜짐 기본값 ↔ 켜짐 — 동작은
     * 같다) '패키지 전체가 바뀜'으로 보고 다시 읽는다 — 켜져 있는데 연결되지 않은 접근성도 이때 다시 연결한다.
     */
    private fun refreshA11yList(context: Context) {
        val pm = context.packageManager
        val refresh = ComponentName(context.packageName, context.packageName)
        try {
            val next = if (pm.getComponentEnabledSetting(refresh) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT else PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            pm.setComponentEnabledSetting(refresh, next, PackageManager.DONT_KILL_APP)
        } catch (e: Exception) {
            Log.w(logTag, "accessibility list refresh failed: ${e.message}")
        }
    }

    /** 입력 제어가 켜져 있는가(Flutter 보고용). 바인딩이 끝나기 전에는 설정 목록으로 판단해 거짓 '꺼짐'을 보내지 않는다. */
    fun isInputOpen(): Boolean {
        if (InputService.isOpen || ready) return true
        if (state != State.BINDING) return false
        val app = appContext ?: return false
        return isHelperListedInSettings(app)
    }

    /** 도우미 입력 제어가 켜져 있는가(홈 카드). 바인딩이 끝나기 전에는 설정 목록으로 판단한다. */
    fun isHelperInputOn(): Boolean {
        if (ready) return true
        if (state != State.BINDING) return false
        val app = appContext ?: return false
        return isHelperListedInSettings(app)
    }

    private fun isHelperListedInSettings(context: Context): Boolean {
        val current = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return current.split(':').any { ComponentName.unflattenFromString(it) == HELPER_INPUT_SERVICE }
    }

    /** adb 권한이 있는 기기에서 도우미 접근성을 켠다(RootUtil.enableInputServiceIfPermitted). 브리지 연결 전이면 연결된 뒤에 켠다
     *  — 연결 전에는 도우미 접근성이 이미 붙어 있는지 몰라 껐다 켜기를 하면 안 된다. */
    fun requestHelperEnable(context: Context) {
        ensureBound(context)
        if (state == State.BOUND) {
            if (!ready) enableHelperNow(context)
        } else {
            pendingEnable = true
        }
    }

    private fun enableHelperNow(context: Context) {
        RootUtil.enableWithRetry(context, HELPER_INPUT_SERVICE) { ready }
    }

    // --- Rust 연결 스레드에서 부른다(MainService.rustPointerInput·rustKeyEventInput). oneway 라 막히지 않는다. ---

    /** 도우미로 보냈으면 true. 아니면 호출한 쪽이 이 앱 InputService 로 보낸다. */
    fun pointer(kind: Int, mask: Int, x: Int, y: Int): Boolean {
        if (!ready) return false
        val r = remote ?: return false
        val scale = SCREEN_INFO.scale
        return try {
            r.pointer(kind, mask, x * scale, y * scale)
            true
        } catch (e: RemoteException) {
            markDead(e)
            false
        }
    }

    /** InputService.onKeyEvent 의 앞부분(protobuf 풀기·글자·KeyEventConverter·볼륨·전원)을 여기서 하고 나머지를 도우미로 보낸다. */
    fun key(data: ByteArray): Boolean {
        if (!ready) return false
        val r = remote ?: return false
        val keyEvent = try {
            KeyEvent.parseFrom(data)
        } catch (e: Exception) {
            Log.w(logTag, "bad key event: ${e.message}")
            return true
        }
        val keyboardMode = keyEvent.getMode()

        var textToCommit: String? = null
        if (keyEvent.hasSeq()) {
            textToCommit = keyEvent.getSeq()
        } else if (keyboardMode == KeyboardMode.Legacy) {
            if (keyEvent.hasChr() && (keyEvent.getDown() || keyEvent.getPress())) {
                textToCommit = String(Character.toChars(keyEvent.getChr()))
            }
        }

        var ke: KeyEventAndroid? = null
        if (Build.VERSION.SDK_INT < 33 || textToCommit == null) {
            ke = KeyEventConverter.toAndroidKeyEvent(keyEvent)
        }
        return try {
            ke?.let { event ->
                if (tryHandleVolumeKeyEvent(event)) return true
                if (event.keyCode == KeyEventAndroid.KEYCODE_POWER) {
                    if (event.action == KeyEventAndroid.ACTION_UP) {
                        r.globalAction(AccessibilityService.GLOBAL_ACTION_POWER_DIALOG)
                    }
                    return true
                }
            }
            r.key(ke, textToCommit, keyEvent.getPress())
            true
        } catch (e: RemoteException) {
            markDead(e)
            false
        }
    }

    // InputService.tryHandleVolumeKeyEvent 와 같다(볼륨은 이 앱 프로세스에서 — 지금과 같은 동작).
    private fun tryHandleVolumeKeyEvent(event: KeyEventAndroid): Boolean {
        val vc = volumeController
        when (event.keyCode) {
            KeyEventAndroid.KEYCODE_VOLUME_UP -> {
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    vc?.raiseVolume(null, true, AudioManager.STREAM_SYSTEM)
                }
                return true
            }
            KeyEventAndroid.KEYCODE_VOLUME_DOWN -> {
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    vc?.lowerVolume(null, true, AudioManager.STREAM_SYSTEM)
                }
                return true
            }
            KeyEventAndroid.KEYCODE_VOLUME_MUTE -> {
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    vc?.toggleMute(true, AudioManager.STREAM_SYSTEM)
                }
                return true
            }
            else -> return false
        }
    }

    /** 화면 공유 동의 창 자동 승인을 도우미에도 켠다(MainService.requestMediaProjection). */
    fun armProjectionAccept(durationMs: Long) {
        armUntil = SystemClock.uptimeMillis() + durationMs
        val r = remote ?: return // 연결되면 남은 시간으로 보낸다
        try {
            r.armProjectionAccept(durationMs)
        } catch (e: RemoteException) {
            markDead(e)
        }
    }

    /** 원격 서비스가 켜졌다·멈췄다(MainService). 켜진 채 이 앱이 죽으면 도우미가 다시 깨운다 — 사용자가 멈춘 뒤에는 깨우지 않는다. */
    fun setMainServiceRunning(running: Boolean) {
        mainServiceRunning = running
        val r = remote ?: return // 연결되면 보낸다
        try {
            r.setMainServiceRunning(running)
        } catch (e: RemoteException) {
            markDead(e)
        }
    }

    /** 입력 제어 끄기(MainActivity 'stop_input'). */
    fun disableInput() {
        val r = remote ?: return
        ready = false
        try {
            r.disableInput()
        } catch (e: RemoteException) {
            markDead(e)
        }
    }
}
