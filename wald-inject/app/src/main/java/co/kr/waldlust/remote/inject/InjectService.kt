package co.kr.waldlust.remote.inject

import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Parcel
import android.util.Log
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * 원격 앱 → 입력 주입 플러그인(부록 A-69, 결정 D47). 원격 앱(WaldInjector.kt)이 바인딩해 포인터 입력을 보낸다.
 * 인터페이스 정본은 flutter/android/app/src/main/aidl.
 *
 * Android 11+ 는 화면에 실제 터치 패널이 없으면 접근성 제스처(dispatchGesture)를 바로 취소한다(isTouchableDisplay). 이 앱은 보드 플랫폼
 * 키로 서명해 INJECT_EVENTS 를 받아 터치를 직접 넣는다(AnyDesk aosp2 와 같은 방식).
 *
 * 플랫폼 서명 앱이라 아무 앱이나 이 서비스를 쓰면 기기 입력 전체를 조작할 수 있다. 원격 앱은 플랫폼 서명이 아니어서 서명 권한으로 막을 수
 * 없으므로, 트랜잭션마다 호출자가 원격 앱 패키지이고 그 서명 인증서가 빌드 때 고정한 값(BuildConfig.CALLER_CERTS)인지 확인한다.
 */
class InjectService : Service() {

    companion object {
        private const val TAG = "WaldInject"
        const val MAIN_PKG = "co.kr.waldlust.remote"
        const val PROTOCOL_VERSION = 1
        // SDK 에서는 숨은 상수(android.Manifest.permission.INJECT_EVENTS)라 문자열로 쓴다
        private const val INJECT_EVENTS = "android.permission.INJECT_EVENTS"

        // uid → 믿을 수 있는 원격 앱인가(초당 수백 번 PackageManager 를 부르지 않게). 원격 앱이 죽으면 비운다.
        private val trustedUids = ConcurrentHashMap<Int, Boolean>()
        private val allowedCerts: Set<String> =
            BuildConfig.CALLER_CERTS.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    }

    private val injector = PointerInjector()
    // 마지막으로 attach 한 원격 앱 표식과 그 죽음 알림
    private var attachedToken: IBinder? = null
    private val deathRecipient = IBinder.DeathRecipient {
        Log.i(TAG, "main app died")
        trustedUids.clear()
        injector.cancel()
    }

    private fun isTrusted(uid: Int): Boolean {
        trustedUids[uid]?.let { return it }
        val ok = packageManager.getPackagesForUid(uid)?.contains(MAIN_PKG) == true && mainSignersAllowed()
        trustedUids[uid] = ok
        if (!ok) Log.w(TAG, "untrusted caller uid=$uid")
        return ok
    }

    private fun mainSignersAllowed(): Boolean {
        if (allowedCerts.isEmpty()) {
            Log.w(TAG, "no caller certificate pinned at build time — refusing all callers")
            return false
        }
        val signers: Array<Signature> = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(MAIN_PKG, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo?.apkContentsSigners ?: return false
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(MAIN_PKG, PackageManager.GET_SIGNATURES).signatures ?: return false
            }
        } catch (e: PackageManager.NameNotFoundException) {
            return false
        }
        return signers.isNotEmpty() && signers.all { sha256(it.toByteArray()) in allowedCerts }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private val binder = object : IWaldInjector.Stub() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code != INTERFACE_TRANSACTION && !isTrusted(Binder.getCallingUid())) {
                throw SecurityException("caller is not the Waldlust remote app")
            }
            return super.onTransact(code, data, reply, flags)
        }

        override fun protocolVersion(): Int = PROTOCOL_VERSION

        override fun canInject(): Boolean =
            checkSelfPermission(INJECT_EVENTS) == PackageManager.PERMISSION_GRANTED

        override fun attach(token: IBinder?) {
            synchronized(this@InjectService) {
                attachedToken?.unlinkToDeath(deathRecipient, 0)
                attachedToken = null
                try {
                    token?.linkToDeath(deathRecipient, 0)
                    attachedToken = token
                } catch (e: Exception) {
                    // 이미 죽은 표식
                    injector.cancel()
                }
            }
        }

        override fun pointer(kind: Int, mask: Int, x: Int, y: Int) {
            injector.pointer(kind, mask, x, y)
        }
    }

    override fun onBind(intent: Intent?): IBinder {
        Log.i(TAG, "bound (pinned callers=${allowedCerts.size})")
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        injector.cancel()
        return false
    }

    override fun onDestroy() {
        synchronized(this) {
            attachedToken?.unlinkToDeath(deathRecipient, 0)
            attachedToken = null
        }
        injector.quit()
        super.onDestroy()
    }
}
