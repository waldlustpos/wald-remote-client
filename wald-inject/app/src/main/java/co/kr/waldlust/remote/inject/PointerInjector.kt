package co.kr.waldlust.remote.inject

import android.app.Instrumentation
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.InputEvent
import android.view.KeyCharacterMap
import android.view.MotionEvent
import android.view.ViewConfiguration
import java.lang.reflect.Method
import kotlin.math.max
import kotlin.math.sign

// 도우미 InputService.kt 와 같은 값(원격 앱이 Rust 에서 받은 그대로 넘긴다)
const val LEFT_DOWN = 9
const val LEFT_MOVE = 8
const val LEFT_UP = 10
const val RIGHT_UP = 18
const val WHEEL_DOWN = 523331
const val WHEEL_UP = 963
// 지금 제어측(Flutter — input_model.dart onPointerSignalImage)의 휠: MOUSE_TYPE_WHEEL(3), 버튼 없음, x·y = 방향(±1, 원격 앱이
// scale 을 곱해 ±2 일 수 있다 — 부호만 쓴다). 위 두 값은 버튼 칸에 ±120 을 넣던 옛 형식이라 지금 제어측 휠은 도우미에서도 먹지 않는다.
const val WHEEL = 3

const val TOUCH_PAN_START = 4
const val TOUCH_PAN_UPDATE = 5
const val TOUCH_PAN_END = 6

/**
 * 원격 앱의 포인터 입력(kind·mask — 도우미 InputService.onMouseInput·onTouchInput 과 같은 뜻)을 터치·휠 이벤트로 바꿔 주입한다.
 *
 * 접근성 제스처는 획을 조각으로 나눠 늦게 보내지만, 여기서는 누름·이동·뗌을 받는 즉시 그대로 넣는다 — 길게 누르기·끌기는 앱이 직접 인식한다.
 * 좌표 처리는 도우미와 같다: 마우스 위치는 이동(mask 0·LEFT_MOVE)에서만 바꾸고 버튼·휠은 마지막 위치에서, 터치 팬 이동은 상대값.
 * 모든 처리는 한 스레드에서 차례로 한다(받은 순서 = 넣는 순서).
 */
class PointerInjector {
    companion object {
        private const val TAG = "WaldInject"
    }

    private val thread = HandlerThread("wald-inject").apply { start() }
    private val handler = Handler(thread.looper)
    private val injector = EventInjector()

    // 아래는 handler 스레드에서만 쓴다.
    private var mouseX = 0
    private var mouseY = 0
    // 눌려 있는 획의 시작 시각(0 = 떼어 있음)
    private var downTime = 0L
    // 오른쪽 클릭(길게 누르기)을 떼는 예약
    private var longPressUp: Runnable? = null
    // 100(tap timeout) + 400(long press timeout) — 도우미의 길게 누르기와 같다
    private val longPressDuration = ViewConfiguration.getTapTimeout().toLong() + ViewConfiguration.getLongPressTimeout().toLong()

    private val touchProps = arrayOf(MotionEvent.PointerProperties().apply {
        id = 0
        toolType = MotionEvent.TOOL_TYPE_FINGER
    })
    private val mouseProps = arrayOf(MotionEvent.PointerProperties().apply {
        id = 0
        toolType = MotionEvent.TOOL_TYPE_MOUSE
    })
    private val coords = arrayOf(MotionEvent.PointerCoords())

    fun pointer(kind: Int, mask: Int, x: Int, y: Int) {
        handler.post {
            if (kind == 0) onTouch(mask, x, y) else onMouse(mask, x, y)
        }
    }

    /** 원격 앱이 죽었다 — 눌린 채 남지 않게 진행 중인 획을 취소한다. */
    fun cancel() {
        handler.post { cancelStroke() }
    }

    fun quit() {
        handler.post { cancelStroke() }
        thread.quitSafely()
    }

    private fun onMouse(mask: Int, x: Int, y: Int) {
        when (mask) {
            0, LEFT_MOVE -> {
                mouseX = max(0, x)
                mouseY = max(0, y)
                if (downTime != 0L && longPressUp == null) touch(MotionEvent.ACTION_MOVE)
            }
            LEFT_DOWN -> {
                finishLongPress()
                if (downTime != 0L) touch(MotionEvent.ACTION_UP) // 뗌을 놓쳤다 — 앞 획을 끝내고 새로
                downTime = SystemClock.uptimeMillis()
                touch(MotionEvent.ACTION_DOWN)
            }
            LEFT_UP -> {
                if (downTime != 0L && longPressUp == null) {
                    touch(MotionEvent.ACTION_UP)
                    downTime = 0L
                }
            }
            RIGHT_UP -> longPress()
            // 도우미의 휠은 120px 밀기(WHEEL_DOWN = 손가락을 위로 = 아래 내용) — 같은 방향의 휠 스크롤
            WHEEL_DOWN -> scroll(-1f, 0f)
            WHEEL_UP -> scroll(1f, 0f)
            // y +1 = 휠을 위로(내용 위로) = AXIS_VSCROLL +, x -1 = 오른쪽(제어측이 부호를 뒤집어 보낸다) = AXIS_HSCROLL +
            WHEEL -> if (x != 0 || y != 0) scroll(y.sign.toFloat(), -x.sign.toFloat())
        }
    }

    private fun onTouch(mask: Int, x: Int, y: Int) {
        when (mask) {
            TOUCH_PAN_START -> {
                finishLongPress()
                if (downTime != 0L) touch(MotionEvent.ACTION_UP)
                mouseX = max(0, x)
                mouseY = max(0, y)
                downTime = SystemClock.uptimeMillis()
                touch(MotionEvent.ACTION_DOWN)
            }
            TOUCH_PAN_UPDATE -> {
                mouseX = max(0, mouseX - x)
                mouseY = max(0, mouseY - y)
                if (downTime != 0L) touch(MotionEvent.ACTION_MOVE)
            }
            TOUCH_PAN_END -> {
                if (downTime != 0L) {
                    touch(MotionEvent.ACTION_UP)
                    downTime = 0L
                }
                mouseX = max(0, x)
                mouseY = max(0, y)
            }
        }
    }

    private fun longPress() {
        if (downTime != 0L) return // 왼쪽 버튼 획 중에는 하지 않는다(손가락 하나)
        downTime = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN)
        val up = Runnable { finishLongPress() }
        longPressUp = up
        handler.postDelayed(up, longPressDuration)
    }

    private fun finishLongPress() {
        val up = longPressUp ?: return
        handler.removeCallbacks(up)
        longPressUp = null
        if (downTime != 0L) {
            touch(MotionEvent.ACTION_UP)
            downTime = 0L
        }
    }

    private fun cancelStroke() {
        longPressUp?.let { handler.removeCallbacks(it) }
        longPressUp = null
        if (downTime != 0L) {
            Log.d(TAG, "cancel ongoing stroke")
            touch(MotionEvent.ACTION_CANCEL)
            downTime = 0L
        }
    }

    private fun touch(action: Int) {
        coords[0].clear()
        coords[0].x = mouseX.toFloat()
        coords[0].y = mouseY.toFloat()
        coords[0].pressure = if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) 0f else 1f
        coords[0].size = 1f
        // deviceId -1(가상) — 기기에 터치 장치가 없어도 그 좌표의 창으로 간다(AnyDesk aosp2 와 같다).
        val event = MotionEvent.obtain(
            downTime, SystemClock.uptimeMillis(), action, 1, touchProps, coords,
            0, 0, 1f, 1f, KeyCharacterMap.VIRTUAL_KEYBOARD, 0, InputDevice.SOURCE_TOUCHSCREEN, 0
        )
        injector.inject(event)
        event.recycle()
    }

    private fun scroll(v: Float, h: Float) {
        coords[0].clear()
        coords[0].x = mouseX.toFloat()
        coords[0].y = mouseY.toFloat()
        coords[0].setAxisValue(MotionEvent.AXIS_VSCROLL, v)
        coords[0].setAxisValue(MotionEvent.AXIS_HSCROLL, h)
        val now = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(
            now, now, MotionEvent.ACTION_SCROLL, 1, mouseProps, coords,
            0, 0, 1f, 1f, KeyCharacterMap.VIRTUAL_KEYBOARD, 0, InputDevice.SOURCE_MOUSE, 0
        )
        injector.inject(event)
        event.recycle()
    }
}

/**
 * InputManager(Android 14+ 는 InputManagerGlobal).injectInputEvent 로 넣는다 — 숨은 API 라 리플렉션(플랫폼 키로 서명된 앱은 숨은 API
 * 제한에서 빠진다). 찾지 못하거나 실패하면 공개 API Instrumentation.sendPointerSync(끝날 때까지 기다림 — 이 스레드에서는 괜찮다)로.
 * 둘 다 INJECT_EVENTS 가 있어야 다른 앱 창에 들어간다.
 */
private class EventInjector {
    companion object {
        private const val TAG = "WaldInject"
        private const val INJECT_INPUT_EVENT_MODE_ASYNC = 0
    }

    private var manager: Any? = null
    private var injectMethod: Method? = null
    private val instrumentation by lazy { Instrumentation() }
    private var failures = 0

    init {
        for (name in arrayOf("android.hardware.input.InputManagerGlobal", "android.hardware.input.InputManager")) {
            try {
                val cls = Class.forName(name)
                val m = cls.getMethod("injectInputEvent", InputEvent::class.java, Int::class.javaPrimitiveType)
                manager = cls.getMethod("getInstance").invoke(null)
                injectMethod = m
                Log.i(TAG, "inject via $name")
                break
            } catch (e: Exception) {
                Log.d(TAG, "$name not usable: $e")
            }
        }
        if (injectMethod == null) Log.w(TAG, "InputManager.injectInputEvent not found — Instrumentation fallback")
    }

    fun inject(event: InputEvent) {
        val m = injectMethod
        if (m != null) {
            try {
                if (m.invoke(manager, event, INJECT_INPUT_EVENT_MODE_ASYNC) as Boolean) return
            } catch (e: Exception) {
                logFailure("injectInputEvent failed: ${e.cause ?: e}")
            }
        }
        try {
            if (event is MotionEvent) instrumentation.sendPointerSync(event)
        } catch (e: Exception) {
            logFailure("sendPointerSync failed: $e")
        }
    }

    // 실패가 계속되면(권한 없음 등) 로그가 넘치지 않게 처음 몇 번만 남긴다.
    private fun logFailure(message: String) {
        if (failures++ < 5) Log.w(TAG, message)
    }
}
