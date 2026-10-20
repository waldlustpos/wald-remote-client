package co.kr.waldlust.remote.helper

/**
 * Waldlust 원격지원 도우미 — 입력 제어(접근성) 서비스(부록 A-44 2단계, 결정 D41).
 *
 * 원격 앱의 flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/InputService.kt(업스트림 RustDesk + 포크의 화면 공유
 * 자동 승인)를 거의 그대로 옮겼다. 접근성이 원격 앱과 다른 패키지에 있어, 원격 앱을 강제 종료해도 시스템이 이 서비스를 끄지 않는다
 * (AnyDesk 접근성 플러그인 ad1 과 같은 구조). 원격 앱은 InputBridgeService 로 입력을 보낸다. 한쪽을 고치면 다른 쪽도 본다.
 *
 * 원본과 다른 점
 * - 좌표: 원격 앱이 SCREEN_INFO.scale 을 곱해서 보낸다(여기서는 곱하지 않는다).
 * - 키: 원격 앱이 protobuf KeyEvent 를 풀어 android KeyEvent·글자로 보낸다(onBridgeKey). 볼륨 키는 원격 앱이, 전원 키는 globalAction 으로.
 * - 입력한 글자는 로그에 남기지 않는다(비밀번호가 들어올 수 있다 — 글자 수만).
 * - 화면 공유 자동 승인은 원격 앱이 armProjectionAccept 로 켜고, 시간이 지나면 이 서비스가 스스로 끈다.
 * - 원격 앱이 죽으면 진행 중인 획을 끝낸다(cancelOngoingGesture — 화면이 눌린 채 남지 않게).
 *
 * Inspired by [droidVNC-NG] https://github.com/bk138/droidVNC-NG
 */

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.widget.EditText
import android.view.accessibility.AccessibilityEvent
import android.view.ViewGroup.LayoutParams
import android.view.accessibility.AccessibilityNodeInfo
import android.view.KeyEvent as KeyEventAndroid
import android.view.ViewConfiguration
import android.graphics.Rect
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.AccessibilityServiceInfo.FLAG_INPUT_METHOD_EDITOR
import android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
import android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
import androidx.annotation.RequiresApi
import java.util.*
import kotlin.math.abs
import kotlin.math.max

const val LEFT_DOWN = 9
const val LEFT_MOVE = 8
const val LEFT_UP = 10
const val RIGHT_UP = 18
// (BUTTON_BACK << 3) | BUTTON_UP
const val BACK_UP = 66
const val WHEEL_BUTTON_DOWN = 33
const val WHEEL_BUTTON_UP = 34
const val WHEEL_DOWN = 523331
const val WHEEL_UP = 963

const val TOUCH_PAN_START = 4
const val TOUCH_PAN_UPDATE = 5
const val TOUCH_PAN_END = 6

const val WHEEL_STEP = 120
const val WHEEL_DURATION = 50L
const val LONG_TAP_DELAY = 200L

class InputService : AccessibilityService() {

    companion object {
        private const val TAG = "WaldHelperInput"

        @Volatile
        var ctx: InputService? = null
        val isOpen: Boolean
            get() = ctx != null

        // 화면공유(MediaProjection) 동의 팝업을 사람 없이 자동 승인한다. 원격 앱이 동의를 요청하기 직전에 armProjectionAccept 로 켜고,
        // 팝업의 "시작/허용" 버튼을 클릭하거나 시간이 지나면 꺼진다(잘못된 다이얼로그 클릭을 막기 위해 시스템UI 창에서만, 짧은 시간창에서만).
        @Volatile
        var autoAcceptProjection = false
        @Volatile
        private var armUntil = 0L
        private val mainHandler = Handler(Looper.getMainLooper())

        // 여러 로케일/버전의 화면공유 승인 버튼 문구.
        val projectionAcceptTexts = listOf(
            "Start now", "START NOW", "Start", "Allow",
            "지금 시작", "시작", "허용", "확인",
            "开始", "立即开始", "确定", "允许",
            "開始", "始める"
        )

        fun armProjectionAccept(durationMs: Long) {
            val ms = durationMs.coerceIn(0L, 60_000L)
            armUntil = SystemClock.uptimeMillis() + ms
            autoAcceptProjection = ms > 0
            Log.d(TAG, "auto-accept armed for ${ms}ms (connected=${ctx != null})")
            // 다시 켜면 앞선 해제 예약이 늦은 시각을 지우지 않도록 만료 시각으로 판단한다.
            mainHandler.postDelayed({
                if (SystemClock.uptimeMillis() >= armUntil) autoAcceptProjection = false
            }, ms)
            // 팝업이 이미 떠 있을 수 있다(신호보다 팝업이 먼저 뜬 경우) — 몇 번 찾아 본다.
            for (delayMs in longArrayOf(0L, 500L, 1500L, 3000L)) {
                mainHandler.postDelayed({ ctx?.tryAutoAcceptProjection() }, delayMs)
            }
        }
    }

    private val logTag = TAG
    private var leftIsDown = false
    private var touchPath = Path()
    private var stroke: GestureDescription.StrokeDescription? = null
    private var lastTouchGestureStartTime = 0L
    private var mouseX = 0
    private var mouseY = 0
    private var timer = Timer()
    private var recentActionTask: TimerTask? = null
    // 100(tap timeout) + 400(long press timeout)
    private val longPressDuration = ViewConfiguration.getTapTimeout().toLong() + ViewConfiguration.getLongPressTimeout().toLong()

    private val wheelActionsQueue = LinkedList<GestureDescription>()
    private var isWheelActionsPolling = false
    private var isWaitingLongPress = false

    private var fakeEditTextForTextStateCalculation: EditText? = null

    private var lastX = 0
    private var lastY = 0

    @RequiresApi(Build.VERSION_CODES.N)
    fun onMouseInput(mask: Int, _x: Int, _y: Int) {
        val x = max(0, _x)
        val y = max(0, _y)

        if (mask == 0 || mask == LEFT_MOVE) {
            val oldX = mouseX
            val oldY = mouseY
            mouseX = x
            mouseY = y
            if (isWaitingLongPress) {
                val delta = abs(oldX - mouseX) + abs(oldY - mouseY)
                Log.d(logTag,"delta:$delta")
                if (delta > 8) {
                    isWaitingLongPress = false
                }
            }
        }

        // left button down, was up
        if (mask == LEFT_DOWN) {
            isWaitingLongPress = true
            timer.schedule(object : TimerTask() {
                override fun run() {
                    if (isWaitingLongPress) {
                        isWaitingLongPress = false
                        continueGesture(mouseX, mouseY)
                    }
                }
            }, longPressDuration)

            leftIsDown = true
            startGesture(mouseX, mouseY)
            return
        }

        // left down, was down
        if (leftIsDown) {
            continueGesture(mouseX, mouseY)
        }

        // left up, was down
        if (mask == LEFT_UP) {
            if (leftIsDown) {
                leftIsDown = false
                isWaitingLongPress = false
                endGesture(mouseX, mouseY)
                return
            }
        }

        if (mask == RIGHT_UP) {
            longPress(mouseX, mouseY)
            return
        }

        if (mask == BACK_UP) {
            performGlobalAction(GLOBAL_ACTION_BACK)
            return
        }

        // long WHEEL_BUTTON_DOWN -> GLOBAL_ACTION_RECENTS
        if (mask == WHEEL_BUTTON_DOWN) {
            timer.purge()
            recentActionTask = object : TimerTask() {
                override fun run() {
                    performGlobalAction(GLOBAL_ACTION_RECENTS)
                    recentActionTask = null
                }
            }
            timer.schedule(recentActionTask, LONG_TAP_DELAY)
        }

        // wheel button up
        if (mask == WHEEL_BUTTON_UP) {
            if (recentActionTask != null) {
                recentActionTask!!.cancel()
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
            return
        }

        if (mask == WHEEL_DOWN) {
            if (mouseY < WHEEL_STEP) {
                return
            }
            val path = Path()
            path.moveTo(mouseX.toFloat(), mouseY.toFloat())
            path.lineTo(mouseX.toFloat(), (mouseY - WHEEL_STEP).toFloat())
            val stroke = GestureDescription.StrokeDescription(
                path,
                0,
                WHEEL_DURATION
            )
            val builder = GestureDescription.Builder()
            builder.addStroke(stroke)
            wheelActionsQueue.offer(builder.build())
            consumeWheelActions()

        }

        if (mask == WHEEL_UP) {
            if (mouseY < WHEEL_STEP) {
                return
            }
            val path = Path()
            path.moveTo(mouseX.toFloat(), mouseY.toFloat())
            path.lineTo(mouseX.toFloat(), (mouseY + WHEEL_STEP).toFloat())
            val stroke = GestureDescription.StrokeDescription(
                path,
                0,
                WHEEL_DURATION
            )
            val builder = GestureDescription.Builder()
            builder.addStroke(stroke)
            wheelActionsQueue.offer(builder.build())
            consumeWheelActions()
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    fun onTouchInput(mask: Int, _x: Int, _y: Int) {
        when (mask) {
            TOUCH_PAN_UPDATE -> {
                mouseX -= _x
                mouseY -= _y
                mouseX = max(0, mouseX);
                mouseY = max(0, mouseY);
                continueGesture(mouseX, mouseY)
            }
            TOUCH_PAN_START -> {
                mouseX = max(0, _x)
                mouseY = max(0, _y)
                startGesture(mouseX, mouseY)
            }
            TOUCH_PAN_END -> {
                endGesture(mouseX, mouseY)
                mouseX = max(0, _x)
                mouseY = max(0, _y)
            }
            else -> {}
        }
    }

    // 원격 앱이 죽었을 때 열린 획(willContinue)이 남아 화면이 눌린 채가 되지 않도록 마지막 위치에서 끝낸다.
    @RequiresApi(Build.VERSION_CODES.N)
    fun cancelOngoingGesture() {
        val wasDown = leftIsDown
        leftIsDown = false
        isWaitingLongPress = false
        if (wasDown || stroke != null) {
            Log.d(logTag, "cancel ongoing gesture")
            endGesture(mouseX, mouseY)
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun consumeWheelActions() {
        if (isWheelActionsPolling) {
            return
        } else {
            isWheelActionsPolling = true
        }
        wheelActionsQueue.poll()?.let {
            dispatchGesture(it, null, null)
            timer.purge()
            timer.schedule(object : TimerTask() {
                override fun run() {
                    isWheelActionsPolling = false
                    consumeWheelActions()
                }
            }, WHEEL_DURATION + 10)
        } ?: let {
            isWheelActionsPolling = false
            return
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun performClick(x: Int, y: Int, duration: Long) {
        val path = Path()
        path.moveTo(x.toFloat(), y.toFloat())
        try {
            val longPressStroke = GestureDescription.StrokeDescription(path, 0, duration)
            val builder = GestureDescription.Builder()
            builder.addStroke(longPressStroke)
            Log.d(logTag, "performClick x:$x y:$y time:$duration")
            dispatchGesture(builder.build(), null, null)
        } catch (e: Exception) {
            Log.e(logTag, "performClick, error:$e")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun longPress(x: Int, y: Int) {
        performClick(x, y, longPressDuration)
    }

    private fun startGesture(x: Int, y: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            touchPath.reset()
        } else {
            touchPath = Path()
        }
        touchPath.moveTo(x.toFloat(), y.toFloat())
        lastTouchGestureStartTime = System.currentTimeMillis()
        lastX = x
        lastY = y
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun doDispatchGesture(x: Int, y: Int, willContinue: Boolean) {
        touchPath.lineTo(x.toFloat(), y.toFloat())
        var duration = System.currentTimeMillis() - lastTouchGestureStartTime
        if (duration <= 0) {
            duration = 1
        }
        try {
            if (stroke == null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    stroke = GestureDescription.StrokeDescription(
                        touchPath,
                        0,
                        duration,
                        willContinue
                    )
                } else {
                    stroke = GestureDescription.StrokeDescription(
                        touchPath,
                        0,
                        duration
                    )
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    stroke = stroke?.continueStroke(touchPath, 0, duration, willContinue)
                } else {
                    stroke = null
                    stroke = GestureDescription.StrokeDescription(
                        touchPath,
                        0,
                        duration
                    )
                }
            }
            stroke?.let {
                val builder = GestureDescription.Builder()
                builder.addStroke(it)
                Log.d(logTag, "doDispatchGesture x:$x y:$y time:$duration")
                dispatchGesture(builder.build(), null, null)
            }
        } catch (e: Exception) {
            Log.e(logTag, "doDispatchGesture, willContinue:$willContinue, error:$e")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun continueGesture(x: Int, y: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            doDispatchGesture(x, y, true)
            touchPath.reset()
            touchPath.moveTo(x.toFloat(), y.toFloat())
            lastTouchGestureStartTime = System.currentTimeMillis()
            lastX = x
            lastY = y
        } else {
            touchPath.lineTo(x.toFloat(), y.toFloat())
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun endGestureBelowO(x: Int, y: Int) {
        try {
            touchPath.lineTo(x.toFloat(), y.toFloat())
            var duration = System.currentTimeMillis() - lastTouchGestureStartTime
            if (duration <= 0) {
                duration = 1
            }
            val stroke = GestureDescription.StrokeDescription(
                touchPath,
                0,
                duration
            )
            val builder = GestureDescription.Builder()
            builder.addStroke(stroke)
            Log.d(logTag, "end gesture x:$x y:$y time:$duration")
            dispatchGesture(builder.build(), null, null)
        } catch (e: Exception) {
            Log.e(logTag, "endGesture error:$e")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun endGesture(x: Int, y: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            doDispatchGesture(x, y, false)
            touchPath.reset()
            stroke = null
        } else {
            endGestureBelowO(x, y)
        }
    }

    // 원본 onKeyEvent(data: ByteArray) 의 뒷부분. 앞부분(protobuf 풀기·글자 만들기·KeyEventConverter·볼륨·전원)은 원격 앱이 한다.
    // ke: API 33 미만이거나 글자가 없을 때의 android KeyEvent(원본과 같은 조건), textToCommit: 넣을 글자, press: 원본 keyEvent.getPress().
    @RequiresApi(Build.VERSION_CODES.N)
    fun onBridgeKey(ke: KeyEventAndroid?, textToCommit: String?, press: Boolean) {
        Log.d(logTag, "onBridgeKey keyCode:${ke?.keyCode} action:${ke?.action} textLen:${textToCommit?.length} press:$press")

        if (Build.VERSION.SDK_INT >= 33) {
            getInputMethod()?.let { inputMethod ->
                inputMethod.getCurrentInputConnection()?.let { inputConnection ->
                    if (textToCommit != null) {
                        textToCommit?.let { text ->
                            inputConnection.commitText(text, 1, null)
                        }
                    } else {
                        ke?.let { event ->
                            inputConnection.sendKeyEvent(event)
                            if (press) {
                                val actionUpEvent = KeyEventAndroid(KeyEventAndroid.ACTION_UP, event.keyCode)
                                inputConnection.sendKeyEvent(actionUpEvent)
                            }
                        }
                    }
                }
            }
        } else {
            val handler = Handler(Looper.getMainLooper())
            handler.post {
                ke?.let { event ->
                    val possibleNodes = possibleAccessibiltyNodes()
                    Log.d(logTag, "possibleNodes:${possibleNodes.size}")
                    for (item in possibleNodes) {
                        val success = trySendKeyEvent(event, item, textToCommit)
                        if (success) {
                            if (press) {
                                val actionUpEvent = KeyEventAndroid(KeyEventAndroid.ACTION_UP, event.keyCode)
                                trySendKeyEvent(actionUpEvent, item, textToCommit)
                            }
                            break
                        }
                    }
                }
            }
        }
    }

    private fun insertAccessibilityNode(list: LinkedList<AccessibilityNodeInfo>, node: AccessibilityNodeInfo) {
        if (list.contains(node)) {
            return
        }
        list.add(node)
    }

    private fun findChildNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) {
            return null
        }
        if (node.isEditable() && node.isFocusable()) {
            return node
        }
        val childCount = node.getChildCount()
        for (i in 0 until childCount) {
            val child = node.getChild(i)
            if (child != null) {
                if (child.isEditable() && child.isFocusable()) {
                    return child
                }
                if (Build.VERSION.SDK_INT < 33) {
                    child.recycle()
                }
            }
        }
        for (i in 0 until childCount) {
            val child = node.getChild(i)
            if (child != null) {
                val result = findChildNode(child)
                if (Build.VERSION.SDK_INT < 33) {
                    if (child != result) {
                        child.recycle()
                    }
                }
                if (result != null) {
                    return result
                }
            }
        }
        return null
    }

    private fun possibleAccessibiltyNodes(): LinkedList<AccessibilityNodeInfo> {
        val linkedList = LinkedList<AccessibilityNodeInfo>()
        val latestList = LinkedList<AccessibilityNodeInfo>()

        val focusInput = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        var focusAccessibilityInput = findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)

        val rootInActiveWindow = getRootInActiveWindow()

        Log.d(logTag, "focusInput:${focusInput != null} focusAccessibilityInput:${focusAccessibilityInput != null} rootInActiveWindow:${rootInActiveWindow != null}")

        if (focusInput != null) {
            if (focusInput.isFocusable() && focusInput.isEditable()) {
                insertAccessibilityNode(linkedList, focusInput)
            } else {
                insertAccessibilityNode(latestList, focusInput)
            }
        }

        if (focusAccessibilityInput != null) {
            if (focusAccessibilityInput.isFocusable() && focusAccessibilityInput.isEditable()) {
                insertAccessibilityNode(linkedList, focusAccessibilityInput)
            } else {
                insertAccessibilityNode(latestList, focusAccessibilityInput)
            }
        }

        val childFromFocusInput = findChildNode(focusInput)

        if (childFromFocusInput != null) {
            insertAccessibilityNode(linkedList, childFromFocusInput)
        }

        val childFromFocusAccessibilityInput = findChildNode(focusAccessibilityInput)
        if (childFromFocusAccessibilityInput != null) {
            insertAccessibilityNode(linkedList, childFromFocusAccessibilityInput)
        }

        if (rootInActiveWindow != null) {
            insertAccessibilityNode(linkedList, rootInActiveWindow)
        }

        for (item in latestList) {
            insertAccessibilityNode(linkedList, item)
        }

        return linkedList
    }

    private fun trySendKeyEvent(event: KeyEventAndroid, node: AccessibilityNodeInfo, textToCommit: String?): Boolean {
        node.refresh()
        this.fakeEditTextForTextStateCalculation?.setSelection(0,0)
        this.fakeEditTextForTextStateCalculation?.setText(null)

        val text = node.getText()
        var isShowingHint = false
        if (Build.VERSION.SDK_INT >= 26) {
            isShowingHint = node.isShowingHintText()
        }

        var textSelectionStart = node.textSelectionStart
        var textSelectionEnd = node.textSelectionEnd

        if (text != null) {
            if (textSelectionStart > text.length) {
                textSelectionStart = text.length
            }
            if (textSelectionEnd > text.length) {
                textSelectionEnd = text.length
            }
            if (textSelectionStart > textSelectionEnd) {
                textSelectionStart = textSelectionEnd
            }
        }

        var success = false

        Log.d(logTag, "existing textLen:${text?.length} textToCommitLen:${textToCommit?.length} textSelectionStart:$textSelectionStart textSelectionEnd:$textSelectionEnd")

        if (textToCommit != null) {
            if ((textSelectionStart == -1) || (textSelectionEnd == -1)) {
                val newText = textToCommit
                this.fakeEditTextForTextStateCalculation?.setText(newText)
                success = updateTextForAccessibilityNode(node)
            } else if (text != null) {
                this.fakeEditTextForTextStateCalculation?.setText(text)
                this.fakeEditTextForTextStateCalculation?.setSelection(
                    textSelectionStart,
                    textSelectionEnd
                )
                this.fakeEditTextForTextStateCalculation?.text?.insert(textSelectionStart, textToCommit)
                success = updateTextAndSelectionForAccessibiltyNode(node)
            }
        } else {
            if (isShowingHint) {
                this.fakeEditTextForTextStateCalculation?.setText(null)
            } else {
                this.fakeEditTextForTextStateCalculation?.setText(text)
            }
            if (textSelectionStart != -1 && textSelectionEnd != -1) {
                Log.d(logTag, "setting selection $textSelectionStart $textSelectionEnd")
                this.fakeEditTextForTextStateCalculation?.setSelection(
                    textSelectionStart,
                    textSelectionEnd
                )
            }

            this.fakeEditTextForTextStateCalculation?.let {
                // This is essiential to make sure layout object is created. OnKeyDown may not work if layout is not created.
                val rect = Rect()
                node.getBoundsInScreen(rect)

                it.layout(rect.left, rect.top, rect.right, rect.bottom)
                it.onPreDraw()
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    val succ = it.onKeyDown(event.getKeyCode(), event)
                    Log.d(logTag, "onKeyDown $succ")
                } else if (event.action == KeyEventAndroid.ACTION_UP) {
                    val success = it.onKeyUp(event.getKeyCode(), event)
                    Log.d(logTag, "keyup $success")
                } else {}
            }

            success = updateTextAndSelectionForAccessibiltyNode(node)
        }
        return success
    }

    fun updateTextForAccessibilityNode(node: AccessibilityNodeInfo): Boolean {
        var success = false
        this.fakeEditTextForTextStateCalculation?.text?.let {
            val arguments = Bundle()
            arguments.putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                it.toString()
            )
            success = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
        }
        return success
    }

    fun updateTextAndSelectionForAccessibiltyNode(node: AccessibilityNodeInfo): Boolean {
        var success = updateTextForAccessibilityNode(node)

        if (success) {
            val selectionStart = this.fakeEditTextForTextStateCalculation?.selectionStart
            val selectionEnd = this.fakeEditTextForTextStateCalculation?.selectionEnd

            if (selectionStart != null && selectionEnd != null) {
                val arguments = Bundle()
                arguments.putInt(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT,
                    selectionStart
                )
                arguments.putInt(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT,
                    selectionEnd
                )
                success = node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, arguments)
                Log.d(logTag, "Update selection to $selectionStart $selectionEnd success:$success")
            }
        }

        return success
    }


    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        // 화면공유 동의 팝업 자동 승인.
        if (!autoAcceptProjection) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED) return
        tryAutoAcceptProjection()
    }

    private fun tryAutoAcceptProjection() {
        if (!autoAcceptProjection) return
        // MediaProjection 동의 팝업은 시스템UI/android 패키지에 뜬다. 다른 앱 팝업 오클릭 방지.
        // OEM(SUNMI 등) 커스텀 ROM 은 systemui 파생 패키지일 수 있어 substring 으로 매칭.
        // 패키지는 이벤트가 아닌 활성 창에서 본다: 창 변경 이벤트(TYPE_WINDOWS_CHANGED)에는 패키지가 없어
        // 이벤트 패키지로 거르면 창 상태 이벤트 때 활성 창이 아직 팝업이 아닐 때 팝업을 놓친다.
        val root = rootInActiveWindow
        if (root == null) {
            Log.d(logTag, "auto-accept: no active window")
            return
        }
        val pkg = root.packageName?.toString() ?: ""
        if (!pkg.contains("systemui") && pkg != "android" && !pkg.contains("mediaprojection")) {
            Log.d(logTag, "auto-accept: skip window $pkg")
            return
        }
        if (tryClickProjectionAccept(root)) {
            autoAcceptProjection = false
            Log.d(logTag, "auto-accepted screen projection dialog")
        } else {
            Log.d(logTag, "auto-accept: accept button not clicked in $pkg (childCount=${root.childCount})")
        }
    }

    // 화면공유 팝업의 "시작/허용" 버튼을 찾아 클릭. 좌표가 아닌 노드(버튼 id/문구) 매칭이라 해상도 무관.
    private fun tryClickProjectionAccept(root: AccessibilityNodeInfo): Boolean {
        // 1) 표준 긍정 버튼 id 우선(android:id/button1)
        try {
            for (n in root.findAccessibilityNodeInfosByViewId("android:id/button1")) {
                if (performClickable(n)) return true
            }
        } catch (_: Exception) {}
        // 2) 문구 매칭(로케일/버전 대응)
        for (t in projectionAcceptTexts) {
            val nodes = try { root.findAccessibilityNodeInfosByText(t) } catch (_: Exception) { continue }
            for (n in nodes) {
                if (performClickable(n)) return true
            }
        }
        return false
    }

    // 노드가 클릭 가능하면 클릭, 아니면 클릭 가능한 부모까지 올라가 클릭.
    private fun performClickable(node: AccessibilityNodeInfo?): Boolean {
        var c = node
        var hops = 0
        while (c != null && hops < 6) {
            if (c.isClickable) {
                val ok = c.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                if (!ok) Log.d(logTag, "auto-accept: click refused on ${c.viewIdResourceName ?: c.text}")
                return ok
            }
            c = c.parent
            hops++
        }
        return false
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        ctx = this
        val info = AccessibilityServiceInfo()
        // FLAG_REPORT_VIEW_IDS: 화면공유 팝업의 표준 버튼(android:id/button1)을 id 로 찾기 위함.
        if (Build.VERSION.SDK_INT >= 33) {
            info.flags = FLAG_INPUT_METHOD_EDITOR or FLAG_RETRIEVE_INTERACTIVE_WINDOWS or FLAG_REPORT_VIEW_IDS
        } else {
            info.flags = FLAG_RETRIEVE_INTERACTIVE_WINDOWS or FLAG_REPORT_VIEW_IDS
        }
        // 화면공유 팝업을 감지하려면 창 변경 이벤트를 받아야 한다(기본 serviceInfo 는 eventTypes=0 이라 onAccessibilityEvent 가 호출되지 않음).
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            AccessibilityEvent.TYPE_WINDOWS_CHANGED
        // Android 7 은 feedbackType 이 0 인 서비스에 이벤트를 보내지 않는다(T2 mini 에서 확인).
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        setServiceInfo(info)
        fakeEditTextForTextStateCalculation = EditText(this)
        // Size here doesn't matter, we won't show this view.
        fakeEditTextForTextStateCalculation?.layoutParams = LayoutParams(100, 100)
        fakeEditTextForTextStateCalculation?.onPreDraw()
        val layout = fakeEditTextForTextStateCalculation?.getLayout()
        Log.d(logTag, "fakeEditTextForTextStateCalculation layout:$layout")
        Log.i(logTag, "onServiceConnected!")
        InputBridgeService.notifyInputState(true)
        // 동의 팝업이 이 서비스 연결보다 먼저 떴을 수 있다 — 연결 직후 몇 번 찾아 승인한다.
        if (autoAcceptProjection) {
            for (delayMs in longArrayOf(0L, 500L, 1500L, 3000L)) {
                mainHandler.postDelayed({ tryAutoAcceptProjection() }, delayMs)
            }
        }
    }

    override fun onDestroy() {
        ctx = null
        Log.i(logTag, "onDestroy")
        InputBridgeService.notifyInputState(false)
        super.onDestroy()
    }

    override fun onInterrupt() {}
}
