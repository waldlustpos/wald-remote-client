package com.carriez.flutter_hbb

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

/**
 * Waldlust(DSK-12 — DSK-08 모바일판): 받은 파일을 기본 앱으로 연다(flutter/lib/common/wald_local_open.dart).
 *
 * Android 7 부터 file:// 를 다른 앱에 넘길 수 없어 FileProvider(content://, 읽기 권한만)로 넘긴다.
 * 실행 파일은 Dart 쪽이 거르고(명세 Q-16 (c)) 여기로 보내지 않는다.
 */
object WaldFiles {
    private const val logTag = "WaldFiles"

    /** 돌려주는 값: "ok" · "not_found" · "no_app"(열 앱 없음) · "failed". */
    fun open(activity: Activity, path: String): String {
        val file = File(path)
        if (!file.isFile) return "not_found"
        return try {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.waldfiles", file)
            val mime = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            "ok"
        } catch (e: ActivityNotFoundException) {
            "no_app"
        } catch (e: Exception) {
            Log.w(logTag, "open failed: ${e.message}")
            "failed"
        }
    }
}
