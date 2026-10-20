package co.kr.waldlust.remote.helper

import android.accessibilityservice.AccessibilityService
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Parcel
import android.os.RemoteCallbackList
import android.util.Log
import android.view.KeyEvent
import java.util.concurrent.ConcurrentHashMap

/**
 * 원격 앱 → 도우미 입력 브리지(부록 A-44 2단계, 결정 D41). 원격 앱(WaldInputBridge.kt)이 바인딩해 원격 입력을 보내고,
 * 도우미 접근성(InputService)의 켜짐·꺼짐을 콜백으로 받는다. 인터페이스 정본은 flutter/android/app/src/main/aidl.
 *
 * 바인딩은 서명 권한(co.kr.waldlust.remote.permission.INPUT_BRIDGE)으로, 트랜잭션마다 호출자가 원격 앱 패키지이고
 * 이 앱과 같은 서명인지 다시 본다(입력에는 비밀번호도 들어온다).
 */
class InputBridgeService : Service() {

    companion object {
        private const val TAG = "WaldHelperBridge"
        const val MAIN_PKG = "co.kr.waldlust.remote"
        const val PROTOCOL_VERSION = 1

        private val mainHandler = Handler(Looper.getMainLooper())
        // uid → 원격 앱·같은 서명 여부(초당 수백 번 PackageManager 를 부르지 않게). 원격 앱이 죽으면 비운다.
        private val trustedUids = ConcurrentHashMap<Int, Boolean>()

        // 원격 앱 서비스가 켜져 있다고 마지막으로 알려 왔는가(MainWatcher 가 되살릴지 정할 때 쓴다).
        @Volatile
        var mainServiceRunning = false

        private val callbacks = object : RemoteCallbackList<IWaldInputCallback>() {
            override fun onCallbackDied(callback: IWaldInputCallback?) {
                Log.i(TAG, "main app callback died")
                trustedUids.clear()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    InputService.ctx?.cancelOngoingGesture()
                }
                MainWatcher.onMainDied("process died")
            }
        }

        // 도우미 접근성이 켜지거나 꺼지면 원격 앱에 알린다. broadcast 는 한 번에 하나만 돌 수 있어 메인 스레드에서 한다.
        fun notifyInputState(connected: Boolean) {
            mainHandler.post {
                val n = callbacks.beginBroadcast()
                try {
                    for (i in 0 until n) {
                        try {
                            callbacks.getBroadcastItem(i).onInputStateChanged(connected)
                        } catch (e: Exception) {
                            Log.w(TAG, "notify failed: $e")
                        }
                    }
                } finally {
                    callbacks.finishBroadcast()
                }
            }
        }
    }

    private fun isTrusted(uid: Int): Boolean {
        trustedUids[uid]?.let { return it }
        val pm = packageManager
        val ok = pm.getPackagesForUid(uid)?.contains(MAIN_PKG) == true &&
            pm.checkSignatures(packageName, MAIN_PKG) == PackageManager.SIGNATURE_MATCH
        trustedUids[uid] = ok
        if (!ok) Log.w(TAG, "untrusted caller uid=$uid")
        return ok
    }

    private val binder = object : IWaldInputBridge.Stub() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code != INTERFACE_TRANSACTION && !isTrusted(Binder.getCallingUid())) {
                throw SecurityException("caller is not the Waldlust remote app")
            }
            return super.onTransact(code, data, reply, flags)
        }

        override fun protocolVersion(): Int = PROTOCOL_VERSION

        override fun isInputConnected(): Boolean = InputService.isOpen

        override fun registerCallback(cb: IWaldInputCallback?) {
            if (cb != null) callbacks.register(cb)
            MainWatcher.onMainRegistered()
        }

        override fun unregisterCallback(cb: IWaldInputCallback?) {
            if (cb != null) callbacks.unregister(cb)
        }

        override fun pointer(kind: Int, mask: Int, x: Int, y: Int) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            val svc = InputService.ctx ?: return
            if (kind == 0) {
                svc.onTouchInput(mask, x, y)
            } else {
                svc.onMouseInput(mask, x, y)
            }
        }

        override fun key(event: KeyEvent?, text: String?, press: Boolean) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            InputService.ctx?.onBridgeKey(event, text, press)
        }

        override fun globalAction(action: Int) {
            if (action != AccessibilityService.GLOBAL_ACTION_POWER_DIALOG) {
                Log.w(TAG, "global action $action not allowed")
                return
            }
            InputService.ctx?.performGlobalAction(action)
        }

        override fun armProjectionAccept(durationMs: Long) {
            InputService.armProjectionAccept(durationMs)
        }

        override fun disableInput() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            Log.i(TAG, "disable input (requested by main app)")
            InputService.ctx?.disableSelf()
        }

        override fun setMainServiceRunning(running: Boolean) {
            mainServiceRunning = running
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder
}
