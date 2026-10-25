package com.carriez.flutter_hbb

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import java.io.File
import java.io.IOException
import kotlin.concurrent.thread

/**
 * Waldlust(DSK-01 — 결정 D44, 부록 A-62): 수신 전용 앱 안 업데이트의 설치.
 *
 * Rust(wald_update.rs)가 어드민에서 받아 SHA-256 을 확인한 APK(앱 데이터 폴더 안)를 PackageInstaller 세션으로 설치한다
 * (도우미 설치 [WaldHelper.install] 과 같은 길 — Android 8+ 는 처음 한 번 '출처를 알 수 없는 앱 설치' 허용).
 * - 시스템 확인 창은 사람이 누른다(현장 직원·원격 운영자). Android 12+ 는 USER_ACTION_NOT_REQUIRED 를 청한다 — 이 앱이
 *   설치 주체이면 확인 없이 설치되고, 조건이 안 되면 확인 창으로 돌아간다.
 * - 설치되면 이 프로세스는 끝난다. 새 버전이 MY_PACKAGE_REPLACED 를 받아, 서비스가 켜져 있었으면 부팅 때와 같은 길로
 *   다시 켠다([WaldUpdatedReceiver]). 도우미(MainWatcher)의 되살리기와 겹쳐도 MainService.isReady 확인으로 한 번만 켜진다.
 */
object WaldSelfUpdate {
    private const val PREFS = "wald_self_update"
    private const val KEY_RESUME_AT = "resume_at"
    private const val KEY_RESUME_SERVICE = "resume_service"
    private const val RESUME_WINDOW_MS = 30 * 60 * 1000L
    const val ACTION_INSTALL_STATUS = "co.kr.waldlust.remote.WALD_SELF_UPDATE_STATUS"
    const val logTag = "WaldSelfUpdate"

    /** '출처를 알 수 없는 앱 설치' 설정에 보냈다 — 허용하고 돌아오면 이 파일로 설치를 이어 간다(MainActivity.onResume). */
    @Volatile
    private var pendingPath: String? = null

    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signersOf(info: PackageInfo): Set<String>? {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.let {
                if (it.hasMultipleSigners()) it.apkContentsSigners else it.signingCertificateHistory?.takeLast(1)?.toTypedArray()
            }
        } else {
            info.signatures
        }
        return signatures?.map { it.toCharsString() }?.toSet()?.takeIf { it.isNotEmpty() }
    }

    /** 설치 전에 받은 APK 를 본다: 이 앱과 같은 패키지·같은 서명·낮지 않은 versionCode. 문제가 있으면 그 이유. */
    private fun checkArchive(context: Context, file: File): String? {
        val pm = context.packageManager
        @Suppress("DEPRECATION")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES
        else PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(file.path, flags) ?: return "archive"
        if (archive.packageName != context.packageName) return "package"
        val installed = try {
            pm.getPackageInfo(context.packageName, flags)
        } catch (e: PackageManager.NameNotFoundException) {
            return "package"
        }
        // 같은 versionCode 는 받는다(같은 빌드를 새 버전으로 속인 목업 시험). 낮으면 Android 가 어차피 거부한다.
        if (versionCodeOf(archive) < versionCodeOf(installed)) return "version"
        // 서명을 읽지 못하면 판단을 PackageInstaller 에 맡긴다(다른 서명이면 설치가 실패한다).
        val archiveSigners = signersOf(archive)
        val installedSigners = signersOf(installed)
        if (archiveSigners != null && installedSigners != null && archiveSigners != installedSigners) return "signature"
        return null
    }

    private fun canRequestInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    /**
     * 설치를 시작한다. 돌려주는 값: "started"(세션 commit 을 백그라운드에서 시작 — 결과는 [WaldSelfUpdateReceiver]),
     * "settings"(출처 허용 화면으로 보냄 — 돌아오면 이어 감), "error:<이유>"(path·archive·package·version·signature).
     */
    fun install(activity: Activity, path: String): String {
        val file = try {
            File(path).canonicalFile
        } catch (e: IOException) {
            return "error:path"
        }
        val dataDir = try {
            File(activity.applicationInfo.dataDir).canonicalFile
        } catch (e: IOException) {
            return "error:path"
        }
        if (!file.isFile || !file.path.startsWith(dataDir.path + File.separator)) return "error:path"
        checkArchive(activity, file)?.let { return "error:$it" }
        if (!canRequestInstall(activity)) {
            pendingPath = file.path
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            )
            return "settings"
        }
        pendingPath = null
        val context = activity.applicationContext
        markResume(context)
        // 50MB 넘는 APK 를 세션에 복사하므로 화면 스레드에서 하지 않는다.
        thread {
            try {
                commit(context, file)
            } catch (e: Exception) {
                Log.w(logTag, "self update failed: ${e.message}")
                clearResume(context)
                notifyFlutter("failed", e.message ?: "")
            }
        }
        return "started"
    }

    private fun commit(context: Context, file: File) {
        val installer = context.packageManager.packageInstaller
        // setPackageSource 는 부르지 않는다(WaldHelper.install 과 같은 까닭 — Android 13·14 의 '제한된 설정').
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val sessionId = installer.createSession(params)
        var committed = false
        try {
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("base.apk", 0, file.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                // 시스템이 결과를 extras 로 채워 보내므로 Android 12+ 는 MUTABLE 이어야 한다(명시적 인텐트).
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                val callback = Intent(context, WaldSelfUpdateReceiver::class.java).setAction(ACTION_INSTALL_STATUS)
                session.commit(PendingIntent.getBroadcast(context, sessionId, callback, flags).intentSender)
                committed = true
            }
            Log.i(logTag, "self update session committed")
        } finally {
            if (!committed) {
                try {
                    installer.abandonSession(sessionId)
                } catch (e: Exception) {
                    Log.w(logTag, "cannot abandon session: ${e.message}")
                }
            }
        }
    }

    /** '출처를 알 수 없는 앱 설치'를 허용하고 돌아왔으면 설치를 이어 간다. */
    fun resumePendingInstall(activity: Activity) {
        val path = pendingPath ?: return
        if (!canRequestInstall(activity)) return
        val result = install(activity, path)
        if (result != "started") notifyFlutter("failed", result)
    }

    /** 설치 전에 '업데이트 뒤 서비스를 다시 켤지'를 남긴다. 프로세스가 곧 끝나므로 바로 쓴다(commit). */
    private fun markResume(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_RESUME_AT, System.currentTimeMillis())
            .putBoolean(KEY_RESUME_SERVICE, MainService.isReady)
            .commit()
    }

    fun clearResume(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    /** 업데이트 뒤 서비스를 다시 켜야 하는가(표식을 읽고 지운다). 오래된 표식은 무시한다. */
    fun takeResume(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val at = prefs.getLong(KEY_RESUME_AT, 0L)
        val service = prefs.getBoolean(KEY_RESUME_SERVICE, false)
        prefs.edit().clear().commit()
        val age = System.currentTimeMillis() - at
        return at > 0L && age in 0..RESUME_WINDOW_MS && service
    }

    /** 설치 결과를 화면에 알린다(server_page.dart androidChannelInit 'wald_self_update_changed'). */
    fun notifyFlutter(event: String, message: String = "") {
        Handler(Looper.getMainLooper()).post {
            MainActivity.flutterMethodChannel?.invokeMethod(
                "wald_self_update_changed", mapOf("event" to event, "message" to message)
            )
        }
    }
}

/** Waldlust(DSK-01 — 결정 D44): 앱 업데이트 세션의 결과. 사용자 확인이 필요하면 시스템 설치 창을 띄운다. */
class WaldSelfUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirm == null) {
                    WaldSelfUpdate.clearResume(context)
                    WaldSelfUpdate.notifyFlutter("failed", "no confirm intent")
                    return
                }
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirm)
                    WaldSelfUpdate.notifyFlutter("confirm")
                } catch (e: Exception) {
                    Log.w(WaldSelfUpdate.logTag, "cannot show install dialog: ${e.message}")
                    WaldSelfUpdate.clearResume(context)
                    WaldSelfUpdate.notifyFlutter("failed", e.message ?: "")
                }
            }
            // 자기 업데이트는 성공하면 대개 이 프로세스가 먼저 끝나 여기까지 오지 않는다(다시 켜기는 WaldUpdatedReceiver).
            PackageInstaller.STATUS_SUCCESS -> Log.i(WaldSelfUpdate.logTag, "self update installed")
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""
                Log.w(WaldSelfUpdate.logTag, "self update status $status: $message")
                WaldSelfUpdate.clearResume(context)
                // BLOCKED: Google Play 프로텍트 등이 막음, ABORTED: 확인 창에서 취소
                WaldSelfUpdate.notifyFlutter(
                    when (status) {
                        PackageInstaller.STATUS_FAILURE_ABORTED -> "aborted"
                        PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
                        PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
                        else -> "failed"
                    }, message
                )
            }
        }
    }
}

/**
 * Waldlust(DSK-01 — 결정 D44): 이 앱이 새 버전으로 바뀐 뒤(MY_PACKAGE_REPLACED — 새 버전 프로세스가 받는다).
 * 앱 안 업데이트 직전에 서비스가 켜져 있었으면 부팅 때와 같은 길(BootReceiver — '부팅 시 시작' 설정·권한 확인)로 다시 켠다.
 * 손으로 덮어 설치한 경우(표식 없음)는 건드리지 않는다. 이 방송은 Android 12+ 백그라운드 포그라운드 서비스 시작 예외다.
 */
class WaldUpdatedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val resume = WaldSelfUpdate.takeResume(context)
        Log.i(WaldSelfUpdate.logTag, "package replaced, resume service: $resume, ready: ${MainService.isReady}")
        if (resume && !MainService.isReady) {
            BootReceiver().onReceive(context, Intent(DEBUG_BOOT_COMPLETED))
        }
    }
}
