package com.carriez.flutter_hbb

import android.Manifest.permission.*
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.media.AudioRecord
import android.media.AudioRecord.READ_BLOCKING
import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
import android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
import android.media.MediaCodecList
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.provider.Settings.*
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat.getSystemService
import com.hjq.permissions.Permission
import com.hjq.permissions.XXPermissions
import ffi.FFI
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.util.*


// intent action, extra
const val ACT_REQUEST_MEDIA_PROJECTION = "REQUEST_MEDIA_PROJECTION"
const val ACT_INIT_MEDIA_PROJECTION_AND_SERVICE = "INIT_MEDIA_PROJECTION_AND_SERVICE"
const val ACT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"
const val EXT_INIT_FROM_BOOT = "EXT_INIT_FROM_BOOT"
const val EXT_MEDIA_PROJECTION_RES_INTENT = "MEDIA_PROJECTION_RES_INTENT"
const val EXT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"

// Activity requestCode
const val REQ_INVOKE_PERMISSION_ACTIVITY_MEDIA_PROJECTION = 101
const val REQ_REQUEST_MEDIA_PROJECTION = 201

// Activity responseCode
const val RES_FAILED = -100

// Flutter channel
const val START_ACTION = "start_action"
const val GET_START_ON_BOOT_OPT = "get_start_on_boot_opt"
const val SET_START_ON_BOOT_OPT = "set_start_on_boot_opt"
const val SYNC_APP_DIR_CONFIG_PATH = "sync_app_dir"
const val GET_VALUE = "get_value"

const val KEY_IS_SUPPORT_VOICE_CALL = "KEY_IS_SUPPORT_VOICE_CALL"

const val KEY_SHARED_PREFERENCES = "KEY_SHARED_PREFERENCES"
const val KEY_START_ON_BOOT_OPT = "KEY_START_ON_BOOT_OPT"
const val KEY_APP_DIR_CONFIG_PATH = "KEY_APP_DIR_CONFIG_PATH"

@SuppressLint("ConstantLocale")
val LOCAL_NAME = Locale.getDefault().toString()
val SCREEN_INFO = Info(0, 0, 1, 200)

data class Info(
    var width: Int, var height: Int, var scale: Int, var dpi: Int
)

fun isSupportVoiceCall(): Boolean {
    // https://developer.android.com/reference/android/media/MediaRecorder.AudioSource#VOICE_COMMUNICATION
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
}

fun requestPermission(context: Context, type: String) {
    XXPermissions.with(context)
        .permission(type)
        .request { _, all ->
            if (all) {
                Handler(Looper.getMainLooper()).post {
                    MainActivity.flutterMethodChannel?.invokeMethod(
                        "on_android_permission_result",
                        mapOf("type" to type, "result" to all)
                    )
                }
            }
        }
}

fun startAction(context: Context, action: String) {
    try {
        context.startActivity(Intent(action).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // don't pass package name when launch ACTION_ACCESSIBILITY_SETTINGS
            if (ACTION_ACCESSIBILITY_SETTINGS != action) {
                data = Uri.parse("package:" + context.packageName)
            }
        })
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

class AudioReader(val bufSize: Int, private val maxFrames: Int) {
    private var currentPos = 0
    private val bufferPool: Array<ByteBuffer>

    init {
        if (maxFrames < 0 || maxFrames > 32) {
            throw Exception("Out of bounds")
        }
        if (bufSize <= 0) {
            throw Exception("Wrong bufSize")
        }
        bufferPool = Array(maxFrames) {
            ByteBuffer.allocateDirect(bufSize)
        }
    }

    private fun next() {
        currentPos++
        if (currentPos >= maxFrames) {
            currentPos = 0
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun readSync(audioRecord: AudioRecord): ByteBuffer? {
        val buffer = bufferPool[currentPos]
        val res = audioRecord.read(buffer, bufSize, READ_BLOCKING)
        return if (res > 0) {
            next()
            buffer
        } else {
            null
        }
    }
}


fun getScreenSize(windowManager: WindowManager) : Pair<Int, Int>{
    var w = 0
    var h = 0
    @Suppress("DEPRECATION")
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val m = windowManager.maximumWindowMetrics
        w = m.bounds.width()
        h = m.bounds.height()
    } else {
        val dm = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(dm)
        w = dm.widthPixels
        h = dm.heightPixels
    }
    return Pair(w, h)
}

// MainActivity 와 MainService 가 함께 부른다. 부팅 후 앱 화면을 한 번도 안 열면
// MainActivity 쪽 호출이 없어 하드웨어 인코더 없이 VP8·반 해상도로 송출되기 때문.
fun setCodecInfo(context: Context) {
    val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    val codecs = codecList.codecInfos
    val codecArray = JSONArray()

    val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    val wh = getScreenSize(windowManager)
    var w = wh.first
    var h = wh.second
    val align = 64
    w = (w + align - 1) / align * align
    h = (h + align - 1) / align * align
    codecs.forEach { codec ->
        val codecObject = JSONObject()
        codecObject.put("name", codec.name)
        codecObject.put("is_encoder", codec.isEncoder)
        var hw: Boolean? = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            hw = codec.isHardwareAccelerated
        } else {
            // https://chromium.googlesource.com/external/webrtc/+/HEAD/sdk/android/src/java/org/webrtc/MediaCodecUtils.java#29
            // https://chromium.googlesource.com/external/webrtc/+/master/sdk/android/api/org/webrtc/HardwareVideoEncoderFactory.java#229
            if (listOf("OMX.google.", "OMX.SEC.", "c2.android").any { codec.name.startsWith(it, true) }) {
                hw = false
            } else if (listOf("c2.qti", "OMX.qcom.video", "OMX.Exynos", "OMX.hisi", "OMX.MTK", "OMX.Intel", "OMX.Nvidia").any { codec.name.startsWith(it, true) }) {
                hw = true
            }
        }
        if (hw != true) {
            return@forEach
        }
        // Rockchip OMX HEVC 인코더(RK3568 Android 11)는 VPS/SPS/PPS 를 내지 않아 FFmpeg 크롭 BSF 가
        // 매 프레임 거부하고, 실패하면 H.264 까지 꺼져 소프트웨어·반 해상도가 된다. 빼서 H.264 하드웨어로 가게 한다.
        if (codec.isEncoder && codec.name.equals("OMX.rk.video_encoder.hevc", true)) {
            return@forEach
        }
        codecObject.put("hw", hw)
        var mime_type = ""
        codec.supportedTypes.forEach { type ->
            if (listOf("video/avc", "video/hevc").contains(type)) { // "video/x-vnd.on2.vp8", "video/x-vnd.on2.vp9", "video/av01"
                mime_type = type;
            }
        }
        if (mime_type.isNotEmpty()) {
            codecObject.put("mime_type", mime_type)
            val caps = codec.getCapabilitiesForType(mime_type)
            if (codec.isEncoder) {
                // Encoder's max_height and max_width are interchangeable
                if (!caps.videoCapabilities.isSizeSupported(w,h) && !caps.videoCapabilities.isSizeSupported(h,w)) {
                    return@forEach
                }
            }
            codecObject.put("min_width", caps.videoCapabilities.supportedWidths.lower)
            codecObject.put("max_width", caps.videoCapabilities.supportedWidths.upper)
            codecObject.put("min_height", caps.videoCapabilities.supportedHeights.lower)
            codecObject.put("max_height", caps.videoCapabilities.supportedHeights.upper)
            val surface = caps.colorFormats.contains(COLOR_FormatSurface);
            codecObject.put("surface", surface)
            val nv12 = caps.colorFormats.contains(COLOR_FormatYUV420SemiPlanar)
            codecObject.put("nv12", nv12)
            if (!(nv12 || surface)) {
                return@forEach
            }
            codecObject.put("min_bitrate", caps.videoCapabilities.bitrateRange.lower / 1000)
            codecObject.put("max_bitrate", caps.videoCapabilities.bitrateRange.upper / 1000)
            if (!codec.isEncoder) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    codecObject.put("low_latency", caps.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency))
                }
            }
            if (!codec.isEncoder) {
                return@forEach
            }
            codecArray.put(codecObject)
        }
    }
    val result = JSONObject()
    result.put("version", Build.VERSION.SDK_INT)
    result.put("w", w)
    result.put("h", h)
    result.put("codecs", codecArray)
    FFI.setCodecInfo(result.toString())
}

 fun translate(input: String): String {
    Log.d("common", "translate:$LOCAL_NAME")
    return FFI.translateLocale(LOCAL_NAME, input)
}