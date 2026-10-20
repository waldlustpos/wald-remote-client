package com.carriez.flutter_hbb

import android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
import android.Manifest.permission.SYSTEM_ALERT_WINDOW
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.Toast
import com.hjq.permissions.XXPermissions
import io.flutter.embedding.android.FlutterActivity

const val DEBUG_BOOT_COMPLETED = "com.carriez.flutter_hbb.DEBUG_BOOT_COMPLETED"

class BootReceiver : BroadcastReceiver() {
    private val logTag = "tagBootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(logTag, "onReceive ${intent.action}")

        if (Intent.ACTION_BOOT_COMPLETED == intent.action || DEBUG_BOOT_COMPLETED == intent.action) {
            // check SharedPreferences config
            // Waldlust(무인 키오스크): "부팅 시 시작"을 기본 ON(키가 없으면 true)으로 본다.
            // 운영자가 명시적으로 끈 경우에만 key=false 로 남아 자동시작을 건너뛴다.
            val prefs = context.getSharedPreferences(KEY_SHARED_PREFERENCES, FlutterActivity.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_START_ON_BOOT_OPT, true)) {
                Log.d(logTag, "KEY_START_ON_BOOT_OPT is false")
                return
            }
            // check pre-permission
            if (!XXPermissions.isGranted(context, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, SYSTEM_ALERT_WINDOW)){
                // Waldlust(무인): 루팅 박스면 필요한 권한을 root 로 확정하고 계속 진행한다.
                // (앱을 한 번도 안 열었어도 설치+루팅+재부팅만으로 자동 동작하게 함)
                RootUtil.ensureUnattendedGrants(context)
                if (!XXPermissions.isGranted(context, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, SYSTEM_ALERT_WINDOW)){
                    Log.d(logTag, "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS or SYSTEM_ALERT_WINDOW is not granted (no root?)")
                    return
                }
            }

            val it = Intent(context, MainService::class.java).apply {
                action = ACT_INIT_MEDIA_PROJECTION_AND_SERVICE
                putExtra(EXT_INIT_FROM_BOOT, true)
            }
            Toast.makeText(context, "Waldlust 원격지원 실행됨", Toast.LENGTH_LONG).show()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(it)
            } else {
                context.startService(it)
            }
        }
    }
}
