package com.carriez.flutter_hbb

import android.Manifest.permission.WRITE_SECURE_SETTINGS
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.File
import java.io.IOException

/**
 * Waldlust(DSK-02 — 부록 A-44, 결정 D40): 원격지원 도우미(co.kr.waldlust.remote.helper) 관리.
 *
 * 도우미는 이 앱을 앱 정보에서 강제 종료한 채 재부팅해도 부팅 때 이 앱을 깨우는 따로인 작은 앱이다(런처 아이콘 없음).
 * - 설치 파일은 이 APK 의 assets/wald-helper.apk 다(빌드 스크립트가 같은 버전·같은 서명으로 넣는다 — 시험 빌드에는 없을 수 있다).
 *   시스템 설치 창으로 설치한다(Android 8+ 는 처음 한 번 이 앱의 '출처를 알 수 없는 앱 설치' 허용).
 * - 새로 설치한 앱은 stopped 라 부팅 신호를 받지 못한다. 아이콘이 없어 사람이 열 수 없으니, 이 앱이 켜질 때·설치가 끝났을 때
 *   도우미에 명시적 신호(ACTIVATE)를 보내 stopped 를 푼다(신호가 전달되면 Android 가 푼다).
 */
object WaldHelper {
    const val PKG = "co.kr.waldlust.remote.helper"
    private const val RECEIVER = "$PKG.BootReceiver"
    private const val ACTION_ACTIVATE = "$PKG.ACTIVATE"
    private const val ASSET = "wald-helper.apk"
    const val ACTION_INSTALL_STATUS = "co.kr.waldlust.remote.WALD_HELPER_INSTALL_STATUS"
    const val logTag = "WaldHelperMgr"

    /** '출처를 알 수 없는 앱 설치' 설정에 보냈다 — 허용하고 돌아오면 설치를 이어 간다(MainActivity.onResume). */
    @Volatile
    private var pendingInstall = false

    @Volatile
    private var bundledVersion: Long? = null

    @Volatile
    private var bundledChecked = false

    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()

    private fun installedVersion(context: Context): Long? = try {
        versionCodeOf(context.packageManager.getPackageInfo(PKG, 0))
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    /** 설치 파일을 캐시로 꺼낸다(버전 읽기·설치용). 이 빌드에 없으면 null. */
    private fun copyBundled(context: Context): File? = try {
        val file = File(context.cacheDir, ASSET)
        context.assets.open(ASSET).use { input -> file.outputStream().use { input.copyTo(it) } }
        file
    } catch (e: IOException) {
        null
    }

    private fun bundledVersion(context: Context): Long? {
        if (!bundledChecked) {
            bundledVersion = copyBundled(context)?.let { file ->
                context.packageManager.getPackageArchiveInfo(file.path, 0)?.let { versionCodeOf(it) }
            }
            bundledChecked = true
        }
        return bundledVersion
    }

    private fun isStopped(context: Context): Boolean = try {
        (context.packageManager.getApplicationInfo(PKG, 0).flags and ApplicationInfo.FLAG_STOPPED) != 0
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /** 도우미가 stopped 면 신호를 보내 푼다(이 앱을 열 때·설치가 끝났을 때). 도우미는 받기만 하고 이 앱을 다시 깨우지 않는다. */
    fun activateIfStopped(context: Context) {
        if (!isStopped(context)) return
        val intent = Intent(ACTION_ACTIVATE).apply {
            component = ComponentName(PKG, RECEIVER)
            addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
        }
        context.sendBroadcast(intent)
        Log.d(logTag, "helper activated")
    }

    private fun canRequestInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    /** 홈 '자동 복구' 카드(flutter/lib/mobile/widgets/wald_helper_card.dart)가 읽는 상태. */
    fun status(context: Context): Map<String, Boolean> {
        activateIfStopped(context)
        val installed = installedVersion(context)
        val bundled = bundledVersion(context)
        return mapOf(
            "installed" to (installed != null),
            "hasBundle" to (bundled != null),
            "needsUpdate" to (installed != null && bundled != null && bundled > installed),
            "adbGranted" to (ContextCompat.checkSelfPermission(context, WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED),
            // 2단계(결정 D41): 도우미에 입력 제어 기능이 있는가 / 도우미 입력 제어가 켜져 있는가
            "inputCapable" to (installed != null && WaldInputBridge.helperInputComponent(context) != null),
            "inputOn" to WaldInputBridge.isHelperInputOn(),
        )
    }

    /**
     * 설치(업데이트)를 시작한다. 돌려주는 값: "started"(시스템 설치 창 — 결과는 [WaldHelperInstallReceiver]),
     * "settings"(출처 허용 화면으로 보냄 — 돌아오면 이어 감), "no_bundle"(이 빌드에 설치 파일 없음), "error".
     */
    fun install(activity: Activity): String {
        val file = copyBundled(activity) ?: return "no_bundle"
        if (!canRequestInstall(activity)) {
            pendingInstall = true
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            )
            return "settings"
        }
        pendingInstall = false
        return try {
            val installer = activity.packageManager.packageInstaller
            // setPackageSource 는 부르지 않는다(UNSPECIFIED): LOCAL_FILE·DOWNLOADED_FILE 로 표시하면 Android 13·14 가 도우미 접근성에
            // '제한된 설정'을 건다. 세션 설치라 지금은 도우미 접근성 토글이 막히지 않는다(2단계 — 결정 D41).
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(PKG)
            }
            val sessionId = installer.createSession(params)
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite(ASSET, 0, file.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                // 시스템이 결과를 extras 로 채워 보내므로 Android 12+ 는 MUTABLE 이어야 한다(명시적 인텐트).
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                val callback = Intent(activity, WaldHelperInstallReceiver::class.java).setAction(ACTION_INSTALL_STATUS)
                session.commit(PendingIntent.getBroadcast(activity, sessionId, callback, flags).intentSender)
            }
            "started"
        } catch (e: Exception) {
            Log.w(logTag, "helper install failed: ${e.message}")
            "error"
        }
    }

    /** '출처를 알 수 없는 앱 설치'를 허용하고 돌아왔으면 설치를 이어 간다. */
    fun resumePendingInstall(activity: Activity) {
        if (pendingInstall && canRequestInstall(activity)) {
            install(activity)
        }
    }

    /** 설치 결과를 홈 카드에 알린다(server_page.dart androidChannelInit 'wald_helper_changed'). */
    fun notifyFlutter(event: String, message: String = "") {
        Handler(Looper.getMainLooper()).post {
            MainActivity.flutterMethodChannel?.invokeMethod(
                "wald_helper_changed", mapOf("event" to event, "message" to message)
            )
        }
    }
}

/** Waldlust(DSK-02 — 결정 D40): 도우미 설치 세션의 결과. 사용자 확인이 필요하면 시스템 설치 창을 띄운다. */
class WaldHelperInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirm == null) {
                    WaldHelper.notifyFlutter("failed", "no confirm intent")
                    return
                }
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirm)
                } catch (e: Exception) {
                    Log.w(WaldHelper.logTag, "cannot show install dialog: ${e.message}")
                    WaldHelper.notifyFlutter("failed", e.message ?: "")
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                Log.d(WaldHelper.logTag, "helper installed")
                WaldHelper.activateIfStopped(context)
                // 2단계: 새 도우미의 입력 제어에 연결하고, adb 권한이 있으면 도우미 접근성을 켠다(이 앱 것은 켜진 뒤 뺀다).
                WaldInputBridge.ensureBound(context)
                RootUtil.enableInputServiceIfPermitted(context)
                WaldHelper.notifyFlutter("installed")
            }
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""
                Log.w(WaldHelper.logTag, "helper install status $status: $message")
                // BLOCKED: Google Play 프로텍트 등이 막음(Android 14 GMS 기기는 도우미를 '유해한 앱'으로 막는다 — 결정 D41, 넘기는 법을 안내)
                WaldHelper.notifyFlutter(
                    when (status) {
                        PackageInstaller.STATUS_FAILURE_ABORTED -> "aborted"
                        PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
                        else -> "failed"
                    }, message
                )
            }
        }
    }
}
