#Requires AutoHotkey v2.0
#SingleInstance Force
; -----------------------------------------------------------------------------
; Fisch fishing helper (external, visual, user-toggled) - AutoHotkey v2
;
; IMPORTANT - READ BEFORE USE:
; - Fisch/Roblox automation rules can change. Check the official Fisch Discord,
;   game description, and Roblox Terms of Use for the current policy on macros.
; - This script is intended as a visual, user-supervised helper (you toggle it
;   on/off and stay at the keyboard). Do NOT use it for unattended automation.
; - External macros can still be disallowed or result in moderation depending on
;   current game/dev rules. Use at your own risk.
;
; NO-CODE SETUP (easy mode):
; 1. Install AutoHotkey v2: https://www.autohotkey.com/
; 2. Put this .ahk file in a folder and double-click it.
; 3. Open Fisch in windowed/borderless and keep the same window size each time.
; 4. Calibrate using hotkeys (settings auto-save to FischMacro.ini next to this file):
;      F2 - Shake setup: hover TOP-LEFT of shake area, press F2; hover BOTTOM-RIGHT, press F2;
;           hover where it should CLICK for shake, press F2.
;      F3 - Reel setup (ONE click): hover the mouse anywhere on the reel bar/track
;           while it is visible, press F3. The script auto-finds the dark-red track
;           row, both edges, and learns the bright-red bar + amber fish colors.
;      F4 - (optional) force the amber fish color: hover the amber fish line, press F4.
;      F5 - (optional) force the bright-red bar color: hover the control bar, press F5.
;      F11 - Auto-cast on/off. After a catch the reel bar disappears; the helper
;            then holds the left mouse button 0.8 s to cast, waits 0.4 s for the
;            fish, and casts again if it does not show up.
;            Shift+F9 / Shift+F10 = wait 0.2 s shorter / longer for the fish.
;      F12 - Mouse input method: "SendInput" (default, what a real mouse uses)
;            or legacy "mouse_event". Only change this if a game ignores the
;            clicks - it never affects detection, only how the button is pressed.
;      Ctrl+F11 / Ctrl+F12 - overlay fainter / more solid (starts at 30%).
;      F7 - Reset saved calibration.
; 5. Press F1 to turn helper ON/OFF. Press Esc to quit.
;
; Tips:
; - If it clicks wrong spot, redo F2. If reel doesn't track, redo F3/F4/F5 while the bar is visible.
; - The overlay at top-left shows status and calibration prompts. The dark part
;   lets clicks go straight through to the game; hold the very light yellow bar
;   above it to drag the whole overlay somewhere else (the spot is remembered).
; -----------------------------------------------------------------------------

; =========================
; Configuration (auto-saved to INI; no coding needed)
; =========================
global CONFIG_PATH := A_ScriptDir "\FischMacro.ini"
; Debug log: only written when a file named "FischMacro.debug" sits next to this script.
global DEBUG_LOG := FileExist(A_ScriptDir "\FischMacro.debug") ? true : false
Dbg("=== script start, AHK " A_AhkVersion " ===")

Dbg(msg) {
    global DEBUG_LOG
    if (!DEBUG_LOG)
        return
    try FileAppend(FormatTime(A_Now, "HH:mm:ss") " " msg "`n", A_ScriptDir "\FischMacro_debug.log")
}

; Self-test mode: set by the --selftest command line (never by normal use).
; It makes the script read saved pictures instead of the screen and stops it
; from clicking or writing the INI file.
global SELFTEST_MODE := false

; -----------------------------------------------------------------------------
; Fast screen pixels.
; PixelGetColor costs ~7 ms per call on some computers, which makes a 600-pixel
; row scan take seconds. This copies a screen region into memory once (one
; BitBlt) and then reads pixels from memory instantly.
; -----------------------------------------------------------------------------
class ScreenBuf {
    hdcScreen := 0
    hdcMem := 0
    hbm := 0
    oldbm := 0
    pbits := 0
    w := 0
    h := 0
    capW := 0
    capH := 0
    bx := 0
    by := 0
    ready := false
    buf := 0
    frozen := false

    Grab(x, y, w, h) {
        if (this.frozen)          ; self-test: a saved image is already loaded
            return true
        if (w <= 0 || h <= 0) {
            this.ready := false
            return false
        }
        if (!this.hdcScreen)
            this.hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        if (!this.hdcMem)
            this.hdcMem := DllCall("gdi32\CreateCompatibleDC", "ptr", this.hdcScreen, "ptr")
        if (!this.hdcScreen || !this.hdcMem) {
            this.ready := false
            return false
        }
        if (this.hbm && (this.capW != w || this.capH != h)) {
            DllCall("gdi32\SelectObject", "ptr", this.hdcMem, "ptr", this.oldbm)
            DllCall("gdi32\DeleteObject", "ptr", this.hbm)
            this.hbm := 0
        }
        if (!this.hbm) {
            bi := Buffer(40, 0)
            NumPut("uint", 40, bi, 0)      ; biSize
            NumPut("int", w, bi, 4)        ; biWidth
            NumPut("int", -h, bi, 8)       ; biHeight (negative = top-down rows)
            NumPut("ushort", 1, bi, 12)    ; biPlanes
            NumPut("ushort", 32, bi, 14)   ; biBitCount
            NumPut("uint", 0, bi, 16)      ; BI_RGB
            NumPut("uint", 0, bi, 20)      ; biSizeImage
            pbits := 0
            this.hbm := DllCall("gdi32\CreateDIBSection", "ptr", this.hdcMem, "ptr", bi, "uint", 0, "ptr*", &pbits, "ptr", 0, "uint", 0, "ptr")
            if (!this.hbm) {
                this.ready := false
                return false
            }
            this.pbits := pbits
            this.oldbm := DllCall("gdi32\SelectObject", "ptr", this.hdcMem, "ptr", this.hbm, "ptr")
            this.capW := w
            this.capH := h
        }
        ok := DllCall("gdi32\BitBlt", "ptr", this.hdcMem, "int", 0, "int", 0, "int", w, "int", h
            , "ptr", this.hdcScreen, "int", x, "int", y, "uint", 0x00CC0020)
        this.bx := x
        this.by := y
        this.w := w
        this.h := h
        this.ready := (ok ? true : false)
        return this.ready
    }

    Has(x, y) {
        return this.ready && (x >= this.bx) && (x < this.bx + this.w) && (y >= this.by) && (y < this.by + this.h)
    }

    Px(x, y) {
        lx := x - this.bx
        ly := y - this.by
        if (lx < 0 || ly < 0 || lx >= this.w || ly >= this.h)
            return -1
        off := (ly * this.w + lx) * 4
        return (NumGet(this.pbits, off + 2, "uchar") << 16) | (NumGet(this.pbits, off + 1, "uchar") << 8) | NumGet(this.pbits, off, "uchar")
    }

    ; Load a raw 32-bit BGRA image (top-down, no padding) as if it were the screen.
    ; Used only by the --selftest mode so the detection code can be checked against
    ; a known picture without needing a real game window on screen.
    LoadBGR(path, w, h) {
        if !FileExist(path)
            return false
        f := FileOpen(path, "r")
        if (!f)
            return false
        need := w * h * 4
        if (f.Length < need) {
            f.Close()
            return false
        }
        this.buf := Buffer(need, 0)
        f.RawRead(this.buf, need)
        f.Close()
        this.pbits := this.buf.Ptr
        this.bx := 0
        this.by := 0
        this.w := w
        this.h := h
        this.capW := w
        this.capH := h
        this.frozen := true
        this.ready := true
        return true
    }
}

global SCR := ScreenBuf()

; Read a pixel: instantly from the last grabbed region, otherwise fall back.
GetPx(x, y) {
    global SCR
    if SCR.Has(x, y)
        return SCR.Px(x, y)
    return PixelGetColor(x, y, "RGB")
}

global SHAKE_ENABLED := false
global REEL_ENABLED := true

; Screen region to scan for the "Shake" prompt/button highlight (pixels).
global SHAKE_X1 := 0
global SHAKE_Y1 := 0
global SHAKE_X2 := 0
global SHAKE_Y2 := 0
global SHAKE_COLOR := 0xFFFFFF
global SHAKE_VARIATION := 40
global SHAKE_CLICK_X := A_ScreenWidth // 2
global SHAKE_CLICK_Y := A_ScreenHeight // 2

; Reel/bar minigame: we scan ONE horizontal line across the dark-red reel track.
; Geometry + colors are auto-detected by pressing F3 once while the reel bar is visible.
global REEL_X1 := 0
global REEL_X2 := 0
global REEL_Y := 0
global REEL_STEP := 1
global REEL_TARGET_COLOR := 0xF8B830   ; amber fish line (auto-learned on F3)
global REEL_TARGET_VARIATION := 60
global REEL_PLAYER_COLOR := 0xB82020   ; bright-red control bar (auto-learned on F3)
global REEL_PLAYER_VARIATION := 60
global REEL_BAR_MERGE_GAP := 60        ; the amber fish line splits the bar in two -> merge it back
global REEL_DEADZONE_PX := 6           ; minimum deadband in pixels
global REEL_DEADBAND_FRAC := 0.10      ; deadband as a fraction of the bar width
global REEL_HOLD_BIAS_PX := 0
global REEL_LOOKAHEAD_MS := 70         ; predict fish movement this far ahead (ms)
global REEL_BAR_LOOKAHEAD_MS := 65     ; predict control-bar drift (inertia) ahead (ms)
global REEL_VEL_SMOOTHING := 0.60      ; 0..1, higher reacts faster to speed changes
global REEL_ACC_SMOOTHING := 0.45      ; 0..1, how much acceleration is tracked
global REEL_ACC_CLAMP := 0.005         ; ignore impossible/noisy accelerations (px/ms^2)
global REEL_SWITCH_GUARD_PX := 5       ; flip input only once the miss is this many px (F9/F10)
global REEL_MIN_SWITCH_MS := 0         ; kept for INI compatibility (unused by predictive mode)

; -----------------------------------------------------------------------------
; Auto-cast. When the fish is caught the reel bar disappears; the helper then
; holds the left mouse button to cast again and keeps at it until the bar (the
; fish) comes back. Hotkeys: F11 on/off, Shift+F9 / Shift+F10 = wait -/+.
; -----------------------------------------------------------------------------
global CAST_ENABLED := true
global CAST_HOLD_MS := 800             ; hold the mouse this long to cast
global CAST_WAIT_MS := 400             ; after casting, wait this long for the fish
global CAST_GONE_MS := 200             ; the fish must be gone this long before casting
global CAST_MAX_TRIES := 12            ; give up after this many casts with no fish

; Timing
global SCAN_INTERVAL_MS := 30
global CLICK_COOLDOWN_MS := 250

; -----------------------------------------------------------------------------
; Mouse input. The helper presses the left mouse button through the same OS call
; a real mouse uses (SendInput) - not a window message - so the game receives a
; normal button press. F12 switches to the older mouse_event API in case a game
; filters one of the two.
; -----------------------------------------------------------------------------
global INPUT_MODE := "input"         ; "input" = SendInput, "event" = mouse_event
SendMode "Input"                     ; mouse + keyboard events go through SendInput
SetMouseDelay -1                     ; no artificial delay on every event
SetKeyDelay -1, -1
CoordMode "Mouse", "Screen"

; Calibration UI state
global calibMode := ""   ; "shake" or "reel"
global calibStep := 0
global calibMsg := ""

; =========================
; State & UI
; =========================
global macroOn := false
global lastClickTime := 0
global reelHolding := false
global reelLastTargetX := ""
global reelLastTargetT := 0
global reelTargetVel := 0
global reelFishAcc := 0
global reelLastPlayerX := ""
global reelLastPlayerT := 0
global reelPlayerVel := 0
global reelPlayerAcc := 0
global reelLastSeenT := 0
global lastFishSeenT := 0                ; last time the reel bar was readable (survives resets)
global reelLastSwitchT := 0
global reelDbg := ""
global reelDbgT := 0

; Auto-cast runtime state
global castPhase := ""                   ; "", "hold" (mouse down), "wait" (fish should appear)
global castPhaseT := 0
global castTries := 0
global castPaused := false
global castMsg := ""
global reelErr := 0
global reelBand := 0

; Status overlay placement (it must never sit on top of the reel bar).
; The overlay is TWO windows: the semi-transparent click-through body with the
; status text, and a light-yellow title strip above it that you can drag.
global OVERLAY_W := 460
global OVERLAY_H := 132                  ; status body height
global OVERLAY_TITLE_H := 22             ; light-yellow drag strip
global OVERLAY_X := 20
global OVERLAY_Y := 20
global OVERLAY_OPACITY := 30             ; whole overlay, percent (Ctrl+F11/F12)
global OVERLAY_PLACED := false           ; true once you have dragged it somewhere

; Developer self-test (not used in normal play):
;   AutoHotkey.exe FischMacro.ahk --selftest <folder with frame_00.bgr ...>
; Loads the saved frames as the "screen", runs the real F3 detection, then runs
; the real reel controller on the following frames and writes selftest.out.
if (A_Args.Length >= 1 && A_Args[1] = "--selftest")
    RunSelfTest(A_Args.Length >= 2 ? A_Args[2] : A_ScriptDir "\selftest")

LoadSettings()

; Light-yellow title strip: the ONLY part of the overlay that takes the mouse,
; so it can be dragged. Everything below it is click-through (clicks reach the
; game/window behind it).
dragGui := Gui("+AlwaysOnTop -Caption +ToolWindow -SysMenu -DPIScale")
dragGui.BackColor := "FFF9C4"            ; very light yellow = the drag handle
dragGui.SetFont("s10 bold c444410", "Segoe UI")
dragText := dragGui.AddText("x6 y2 w448 h18", "FISCH HELPER  -  hold this bar to drag me")

statusGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")   ; E0x20 = click-through
statusGui.BackColor := "14181C"
statusGui.SetFont("s10 cWhite", "Segoe UI")
statusText := statusGui.AddText("w440 h120", "")
UpdateStatus()
statusGui.Show("w" OVERLAY_W " h" OVERLAY_H " NoActivate")
dragGui.Show("w" OVERLAY_W " h" OVERLAY_TITLE_H " NoActivate")
ApplyOverlayOpacity()
PlaceOverlay()

; Dragging: hold the light-yellow bar. WM_LBUTTONDOWN = 0x0201.
OnMessage(0x0201, OnOverlayLButtonDown)

SetTimer(ScanLoop, SCAN_INTERVAL_MS)
SetTimer(RefreshOverlay, 250)
OnExit(Cleanup)

RefreshOverlay() {
    global macroOn
    if (macroOn)
        UpdateStatus()
}

F1::ToggleMacro()
F2::CalibrateShake()
F3::CalibrateReel()
F4::CalibrateReelTarget()
F5::CalibrateReelPlayer()
F6::AdjustLookahead(-10)
F8::AdjustLookahead(10)
F9::AdjustDeadzone(-2)
F10::AdjustDeadzone(2)
F11::ToggleCast()
+F9::AdjustCastWait(-200)
+F10::AdjustCastWait(200)
F12::ToggleInputMode()
^F11::AdjustOpacity(-10)
^F12::AdjustOpacity(10)
F7::ResetCalibration()
Esc::ExitApp()

AdjustLookahead(delta) {
    global REEL_LOOKAHEAD_MS, calibMsg
    REEL_LOOKAHEAD_MS := Max(0, Min(300, REEL_LOOKAHEAD_MS + delta))
    calibMsg := "Prediction/lookahead: " REEL_LOOKAHEAD_MS " ms (F6 less, F8 more)"
    SaveSettings()
    UpdateStatus()
}

AdjustDeadzone(delta) {
    global REEL_SWITCH_GUARD_PX, calibMsg
    REEL_SWITCH_GUARD_PX := Max(0, Min(40, REEL_SWITCH_GUARD_PX + delta))
    calibMsg := "Steadiness: switch at " REEL_SWITCH_GUARD_PX "px off-centre (F9 sharper, F10 steadier)"
    SaveSettings()
    UpdateStatus()
}

ToggleCast() {
    global CAST_ENABLED, calibMsg, castPhase, castTries, castPaused, castMsg
    CAST_ENABLED := !CAST_ENABLED
    castPhase := "", castTries := 0, castPaused := false, castMsg := ""
    calibMsg := "Auto-cast " (CAST_ENABLED ? "ON" : "OFF") " (F11)"
    SaveSettings()
    UpdateStatus()
}

AdjustCastWait(delta) {
    global CAST_WAIT_MS, calibMsg
    CAST_WAIT_MS := Max(200, Min(6000, CAST_WAIT_MS + delta))
    calibMsg := "Auto-cast: wait " CAST_WAIT_MS " ms for the fish (Shift+F9 shorter, Shift+F10 longer)"
    SaveSettings()
    UpdateStatus()
}

; F12: switch the mouse injection path. Both are normal OS input (the game sees a
; real button press); SendInput is the modern path a physical mouse uses,
; mouse_event is the older one some games still accept when they filter SendInput.
ToggleInputMode() {
    global INPUT_MODE, calibMsg
    INPUT_MODE := (INPUT_MODE = "event") ? "input" : "event"
    if (INPUT_MODE = "event")
        calibMsg := "Mouse input: legacy mouse_event (F12 back to SendInput)"
    else
        calibMsg := "Mouse input: SendInput, same as a real mouse (F12 for legacy)"
    Dbg("input mode -> " INPUT_MODE)
    SaveSettings()
    UpdateStatus()
}

; 30% by default; Ctrl+F11 = fainter, Ctrl+F12 = more solid. Both windows get
; the same transparency so the overlay reads as one panel.
ApplyOverlayOpacity() {
    global statusGui, dragGui, OVERLAY_OPACITY
    alpha := Round(255 * Max(10, Min(100, OVERLAY_OPACITY)) / 100)
    try WinSetTransparent(alpha, "ahk_id " statusGui.Hwnd)
    try WinSetTransparent(alpha, "ahk_id " dragGui.Hwnd)
}

; Move the title strip and the status body together (they are separate windows).
MoveOverlay(x, y) {
    global statusGui, dragGui, OVERLAY_W, OVERLAY_H, OVERLAY_TITLE_H
    global OVERLAY_X, OVERLAY_Y, SELFTEST_MODE
    if (SELFTEST_MODE)
        return
    x := Max(0, Min(A_ScreenWidth - OVERLAY_W, x))
    y := Max(0, Min(A_ScreenHeight - OVERLAY_TITLE_H - OVERLAY_H, y))
    Dbg("overlay -> " x "," y " (screen " A_ScreenWidth "x" A_ScreenHeight ")")
    OVERLAY_X := x
    OVERLAY_Y := y
    try dragGui.Move(x, y, OVERLAY_W, OVERLAY_TITLE_H)
    try statusGui.Move(x, y + OVERLAY_TITLE_H, OVERLAY_W, OVERLAY_H)
}

OnOverlayLButtonDown(wParam, lParam, msg, hwnd) {
    global dragGui, dragText, SELFTEST_MODE
    if (SELFTEST_MODE)
        return
    if (hwnd = dragGui.Hwnd || hwnd = dragText.Hwnd)
        StartOverlayDrag()
}

StartOverlayDrag() {
    global OVERLAY_X, OVERLAY_Y
    MouseGetPos(&mx, &my)
    Dbg("drag start: mouse " mx "," my " overlay " OVERLAY_X "," OVERLAY_Y)
    offX := mx - OVERLAY_X
    offY := my - OVERLAY_Y
    while GetKeyState("LButton", "P") {
        MouseGetPos(&mx, &my)
        MoveOverlay(mx - offX, my - offY)
        Sleep(10)
    }
    SaveSettings()                  ; remember where it was left
    Dbg("drag end: overlay " OVERLAY_X "," OVERLAY_Y)
    UpdateStatus()
}

AdjustOpacity(delta) {
    global OVERLAY_OPACITY, calibMsg
    OVERLAY_OPACITY := Max(10, Min(100, OVERLAY_OPACITY + delta))
    ApplyOverlayOpacity()
    calibMsg := "Overlay: " OVERLAY_OPACITY "% opacity (Ctrl+F11 fainter, Ctrl+F12 stronger)"
    SaveSettings()
    UpdateStatus()
}

Cleanup(*) {
    ReleaseReel()
}

; Keep the status box out of the way of the reel bar (it is always-on-top, so if
; it covered the bar the macro would read the overlay instead of the game).
; Once you drag it somewhere yourself, that position is respected instead.
PlaceOverlay() {
    global REEL_X1, REEL_X2, REEL_Y, OVERLAY_X, OVERLAY_Y, OVERLAY_PLACED
    global OVERLAY_W, OVERLAY_H, OVERLAY_TITLE_H, SELFTEST_MODE
    if (SELFTEST_MODE)
        return
    x := OVERLAY_X
    y := OVERLAY_Y
    if (!OVERLAY_PLACED) {
        totalH := OVERLAY_TITLE_H + OVERLAY_H
        x := 20, y := 20
        if (REEL_Y > 0 && REEL_X1 > 0) {
            overlapY := (REEL_Y + 50 > y) && (REEL_Y - 50 < y + totalH)
            overlapX := (REEL_X2 > x) && (REEL_X1 < x + OVERLAY_W)
            if (overlapX && overlapY)
                y := Max(0, A_ScreenHeight - totalH - 80)
        }
    }
    MoveOverlay(x, y)
}

ResetReelTracking() {
    global reelLastTargetX := "", reelLastTargetT := 0, reelTargetVel := 0, reelFishAcc := 0
    global reelLastPlayerX := "", reelLastPlayerT := 0, reelPlayerVel := 0, reelPlayerAcc := 0
    global reelLastSeenT := 0, reelLastSwitchT := 0
}

LoadSettings() {
    global
    if !FileExist(CONFIG_PATH)
        return
    try {
        SHAKE_X1 := Integer(IniRead(CONFIG_PATH, "Shake", "X1", SHAKE_X1))
        SHAKE_Y1 := Integer(IniRead(CONFIG_PATH, "Shake", "Y1", SHAKE_Y1))
        SHAKE_X2 := Integer(IniRead(CONFIG_PATH, "Shake", "X2", SHAKE_X2))
        SHAKE_Y2 := Integer(IniRead(CONFIG_PATH, "Shake", "Y2", SHAKE_Y2))
        SHAKE_CLICK_X := Integer(IniRead(CONFIG_PATH, "Shake", "ClickX", SHAKE_CLICK_X))
        SHAKE_CLICK_Y := Integer(IniRead(CONFIG_PATH, "Shake", "ClickY", SHAKE_CLICK_Y))
        ; Old two-click reel geometry cannot be reused by the new detection.
        geomVer := Integer(IniRead(CONFIG_PATH, "Reel", "GeomVersion", 1))
        if (geomVer >= 2) {
            REEL_X1 := Integer(IniRead(CONFIG_PATH, "Reel", "X1", REEL_X1))
            REEL_X2 := Integer(IniRead(CONFIG_PATH, "Reel", "X2", REEL_X2))
            REEL_Y := Integer(IniRead(CONFIG_PATH, "Reel", "Y", REEL_Y))
            REEL_TARGET_COLOR := Integer(IniRead(CONFIG_PATH, "Reel", "TargetColor", REEL_TARGET_COLOR))
            REEL_PLAYER_COLOR := Integer(IniRead(CONFIG_PATH, "Reel", "PlayerColor", REEL_PLAYER_COLOR))
        } else {
            REEL_X1 := 0, REEL_X2 := 0, REEL_Y := 0
            calibMsg := "Update installed: press F3 once on the reel bar to recalibrate."
        }
        ; Controller tuning changed shape (predictive switching + learned bar
        ; acceleration). Only reuse saved tuning from the same version; the
        ; calibrated screen geometry above is kept either way.
        tuneVer := Integer(IniRead(CONFIG_PATH, "Reel", "TuneVersion", 1))
        if (tuneVer >= 2) {
            REEL_LOOKAHEAD_MS := Integer(IniRead(CONFIG_PATH, "Reel", "LookaheadMs", REEL_LOOKAHEAD_MS))
            REEL_SWITCH_GUARD_PX := Integer(IniRead(CONFIG_PATH, "Reel", "SwitchGuardPx", REEL_SWITCH_GUARD_PX))
        }
        CAST_ENABLED := Integer(IniRead(CONFIG_PATH, "Cast", "Enabled", CAST_ENABLED ? 1 : 0)) = 1
        CAST_WAIT_MS := Integer(IniRead(CONFIG_PATH, "Cast", "WaitMs", CAST_WAIT_MS))
        mode := IniRead(CONFIG_PATH, "Input", "Mode", INPUT_MODE)
        if (mode = "event" || mode = "input")
            INPUT_MODE := mode
        OVERLAY_OPACITY := Max(10, Min(100, Integer(IniRead(CONFIG_PATH, "Overlay", "Opacity", OVERLAY_OPACITY))))
        ovX := IniRead(CONFIG_PATH, "Overlay", "X", "")
        ovY := IniRead(CONFIG_PATH, "Overlay", "Y", "")
        if (ovX != "" && ovY != "") {
            OVERLAY_X := Integer(ovX)
            OVERLAY_Y := Integer(ovY)
            OVERLAY_PLACED := true
        }
    } catch {
    }
}

SaveSettings() {
    global CONFIG_PATH, SELFTEST_MODE
    global SHAKE_X1, SHAKE_Y1, SHAKE_X2, SHAKE_Y2, SHAKE_CLICK_X, SHAKE_CLICK_Y
    global REEL_X1, REEL_X2, REEL_Y, REEL_TARGET_COLOR, REEL_PLAYER_COLOR
    global REEL_LOOKAHEAD_MS, REEL_SWITCH_GUARD_PX
    global CAST_ENABLED, CAST_WAIT_MS
    global INPUT_MODE
    global OVERLAY_X, OVERLAY_Y, OVERLAY_OPACITY
    if (SELFTEST_MODE)
        return
    try {
        IniWrite(SHAKE_X1, CONFIG_PATH, "Shake", "X1")
        IniWrite(SHAKE_Y1, CONFIG_PATH, "Shake", "Y1")
        IniWrite(SHAKE_X2, CONFIG_PATH, "Shake", "X2")
        IniWrite(SHAKE_Y2, CONFIG_PATH, "Shake", "Y2")
        IniWrite(SHAKE_CLICK_X, CONFIG_PATH, "Shake", "ClickX")
        IniWrite(SHAKE_CLICK_Y, CONFIG_PATH, "Shake", "ClickY")
        IniWrite(REEL_X1, CONFIG_PATH, "Reel", "X1")
        IniWrite(REEL_X2, CONFIG_PATH, "Reel", "X2")
        IniWrite(REEL_Y, CONFIG_PATH, "Reel", "Y")
        IniWrite(2, CONFIG_PATH, "Reel", "GeomVersion")
        IniWrite(Format("0x{:06X}", REEL_TARGET_COLOR & 0xFFFFFF), CONFIG_PATH, "Reel", "TargetColor")
        IniWrite(Format("0x{:06X}", REEL_PLAYER_COLOR & 0xFFFFFF), CONFIG_PATH, "Reel", "PlayerColor")
        IniWrite(REEL_LOOKAHEAD_MS, CONFIG_PATH, "Reel", "LookaheadMs")
        IniWrite(REEL_SWITCH_GUARD_PX, CONFIG_PATH, "Reel", "SwitchGuardPx")
        IniWrite(2, CONFIG_PATH, "Reel", "TuneVersion")
        IniWrite(CAST_ENABLED ? 1 : 0, CONFIG_PATH, "Cast", "Enabled")
        IniWrite(CAST_WAIT_MS, CONFIG_PATH, "Cast", "WaitMs")
        IniWrite(INPUT_MODE, CONFIG_PATH, "Input", "Mode")
        IniWrite(OVERLAY_X, CONFIG_PATH, "Overlay", "X")
        IniWrite(OVERLAY_Y, CONFIG_PATH, "Overlay", "Y")
        IniWrite(OVERLAY_OPACITY, CONFIG_PATH, "Overlay", "Opacity")
    } catch as e {
        TrayTip("Fisch Helper", "Could not save settings: " e.Message, 3)
    }
}

CalibrateShake() {
    global calibMode, calibStep, calibMsg
    MouseGetPos(&mx, &my)
    if (calibMode != "shake")
        calibStep := 0
    calibMode := "shake"
    calibStep += 1
    if (calibStep = 1) {
        global SHAKE_X1 := mx, SHAKE_Y1 := my
        calibMsg := "Shake: top-left saved. Hover BOTTOM-RIGHT of shake area, press F2."
    } else if (calibStep = 2) {
        global SHAKE_X2 := mx, SHAKE_Y2 := my
        ; normalize
        if (SHAKE_X2 < SHAKE_X1) {
            tmp := SHAKE_X1
            SHAKE_X1 := SHAKE_X2
            SHAKE_X2 := tmp
        }
        if (SHAKE_Y2 < SHAKE_Y1) {
            tmp := SHAKE_Y1
            SHAKE_Y1 := SHAKE_Y2
            SHAKE_Y2 := tmp
        }
        calibMsg := "Shake: area saved. Hover where it should CLICK, press F2."
    } else {
        global SHAKE_CLICK_X := mx, SHAKE_CLICK_Y := my
        calibMsg := "Shake calibration saved."
        calibMode := "", calibStep := 0
        SaveSettings()
    }
    UpdateStatus()
}

; One-click reel setup: press F3 while the reel bar is visible (mouse anywhere).
; Finds the dark-red track row + its horizontal extent, learns the exact
; bright-red bar color and amber fish color, then verifies it can read both.
CalibrateReel() {
    global REEL_X1, REEL_X2, REEL_Y
    global REEL_TARGET_COLOR, REEL_PLAYER_COLOR
    global calibMode, calibStep, calibMsg, SELFTEST_MODE

    MouseGetPos(&mx, &my)
    Dbg("F3 pressed at " mx "," my)
    calibMode := "", calibStep := 0
    calibMsg := "Reel: scanning for the reel bar..."
    UpdateStatus()

    ; Keep the old setup: a failed scan must not destroy a working calibration.
    oldX1 := REEL_X1, oldX2 := REEL_X2, oldY := REEL_Y
    oldBar := REEL_PLAYER_COLOR, oldFish := REEL_TARGET_COLOR

    t0 := A_TickCount
    goodRow := 0

    if (SELFTEST_MODE) {
        if (FindReelTrack(0, 0, A_ScreenWidth, A_ScreenHeight, 16)) {
            LearnReelColors(REEL_X1, REEL_X2, REEL_Y)
            goodRow := ReadReelTestRow()
        }
    } else {
        ; 1) near the mouse first (fast), 2) then everywhere, verifying each result
        if (FindReelTrack(mx - 430, my - 70, 860, 140, 10)) {
            LearnReelColors(REEL_X1, REEL_X2, REEL_Y)
            goodRow := ReadReelTestRow()
        }
        if (goodRow = 0 && FindReelTrack(0, 0, A_ScreenWidth, A_ScreenHeight, 16)) {
            LearnReelColors(REEL_X1, REEL_X2, REEL_Y)
            goodRow := ReadReelTestRow()
        }
    }
    Dbg("F3 scan done in " (A_TickCount - t0) " ms, goodRow=" goodRow)

    if (goodRow = 0) {
        REEL_X1 := oldX1, REEL_X2 := oldX2, REEL_Y := oldY
        REEL_PLAYER_COLOR := oldBar, REEL_TARGET_COLOR := oldFish
        Dbg("F3 FAILED - geometry restored to " REEL_X1 "-" REEL_X2 "@" REEL_Y)
        calibMsg := "Reel: not found. Show the reel bar (red bar + amber fish) and press F3 again."
        UpdateStatus()
        return
    }

    REEL_Y := goodRow
    bar := FindBarSpan(REEL_X1, REEL_X2, REEL_Y, REEL_PLAYER_COLOR, REEL_PLAYER_VARIATION, REEL_STEP, REEL_BAR_MERGE_GAP)
    fish := FindFishX(REEL_X1, REEL_X2, REEL_Y, REEL_TARGET_COLOR, REEL_TARGET_VARIATION, REEL_STEP, bar.center)
    Dbg("F3 OK track=" REEL_X1 "-" REEL_X2 "@" REEL_Y " bar=" bar.center "/w" bar.width " fish=" fish.x
        " barColor=" Format("0x{:06X}", REEL_PLAYER_COLOR) " fishColor=" Format("0x{:06X}", REEL_TARGET_COLOR))
    calibMsg := "Reel READY - track " REEL_X1 "-" REEL_X2 " @y" REEL_Y ", bar " bar.width "px, fish x" fish.x ". Press F1 to run."
    PlaceOverlay()
    SaveSettings()
    UpdateStatus()
}

; Can the control bar AND the fish be read on the track row (or a neighbour)?
; Returns 0 when not readable, otherwise the row that works. Used by F3 so a wrong
; row is never saved.
ReadReelTestRow() {
    global REEL_X1, REEL_X2, REEL_Y, REEL_STEP, REEL_BAR_MERGE_GAP, SCR
    global REEL_TARGET_COLOR, REEL_PLAYER_COLOR, REEL_TARGET_VARIATION, REEL_PLAYER_VARIATION

    for dy in [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6] {
        yy := REEL_Y + dy
        if (!SCR.Has(REEL_X1, yy))
            continue
        bar := FindBarSpan(REEL_X1, REEL_X2, yy, REEL_PLAYER_COLOR, REEL_PLAYER_VARIATION, REEL_STEP, REEL_BAR_MERGE_GAP)
        if (!bar.found)
            continue
        fish := FindFishX(REEL_X1, REEL_X2, yy, REEL_TARGET_COLOR, REEL_TARGET_VARIATION, REEL_STEP, bar.center)
        if (!fish.found)
            continue
        return yy
    }
    return 0
}

; Find the reel track inside a screen rectangle. Sets REEL_X1/REEL_X2/REEL_Y.
;
; The bright-red control bar is the landmark, NOT dark red: dark red is also used
; by health bars, red UI text and wallpaper, which used to make F3 pick the wrong
; row. A candidate row is only accepted when it has a bright bar AND dark-red
; track on at least one side of that bar (a plain red bar has no track around it).
FindReelTrack(x, y, w, h, colStep) {
    global REEL_X1, REEL_X2, REEL_Y, SCR, REEL_BAR_MERGE_GAP

    x := Max(0, x)
    y := Max(0, y)
    w := Min(w, A_ScreenWidth - x)
    h := Min(h, A_ScreenHeight - y)
    if (w < 200 || h < 30)
        return false
    if (!SCR.Grab(x, y, w, h))
        return false

    x2 := x + w - 1
    samples := Max(1, w // colStep)
    minBar := Max(3, Round(samples * 0.02))

    ; --- pass 1: rows that contain bright-bar pixels (coarse) ---
    rowStep := (h > 300) ? 2 : 1
    cand := []
    yy := y
    while (yy < y + h) {
        bars := 0
        track := 0
        xx := x
        while (xx <= x2) {
            c := GetPx(xx, yy)
            if IsBarPixel(c, c, 0)
                bars += 1
            else if IsDarkRedPixel(c)
                track += 1
            xx += colStep
        }
        ; A real reel row has a bright bar AND dark-red track around it. Requiring
        ; the track here stops a wide red health bar / red UI panel from filling
        ; the whole candidate list and hiding the real widget.
        if (bars >= minBar && track >= minBar)
            cand.Push({ y: yy, bars: bars, track: track })
        yy += rowStep
    }

    ; --- pass 2: strongest rows first, refined to 1 px and fully verified ---
    cand := SortCandidates(cand)
    for idx, cnd in cand {
        if (idx > 24)
            break
        rowY := RefineBarRow(x, x2, cnd.y, rowStep)
        ext := WidestReelSpan(x, x2, rowY, 12)
        if (ext.right - ext.left < 150)
            continue
        bar := FindBarSpan(ext.left, ext.right, rowY, "", 0, 1, REEL_BAR_MERGE_GAP)
        if (!bar.found)
            continue
        leftDark := CountDarkRed(ext.left, bar.left - 1, rowY)
        rightDark := CountDarkRed(bar.right + 1, ext.right, rowY)
        if (leftDark + rightDark < 40 || Max(leftDark, rightDark) < 15)
            continue
        REEL_X1 := ext.left
        REEL_X2 := ext.right
        REEL_Y := rowY
        Dbg("track candidate y=" rowY " bars=" cnd.bars " ext=" ext.left "-" ext.right " darkL=" leftDark " darkR=" rightDark)
        return true
    }

    ; --- fallback: no bright bar visible, so use the widest dark-red track ---
    bestY := -1
    bestScore := -1
    yy := y
    while (yy < y + h) {
        score := 0
        xx := x
        while (xx <= x2) {
            if IsReelPixel(GetPx(xx, yy))
                score += 1
            xx += colStep
        }
        if (score > bestScore) {
            bestScore := score
            bestY := yy
        }
        yy += rowStep
    }
    if (bestScore < Max(10, samples * 0.15))
        return false
    rowY := RefineBarRow(x, x2, bestY, rowStep)          ; reuse: most reel pixels
    ext := WidestReelSpan(x, x2, rowY, 20, true)         ; dark red only
    if (ext.right - ext.left < 150)
        return false
    REEL_X1 := ext.left
    REEL_X2 := ext.right
    REEL_Y := rowY
    Dbg("track fallback (no bright bar) y=" rowY " ext=" ext.left "-" ext.right)
    return true
}

; Widest horizontal span of reel pixels on one row, bridging gaps up to maxGap.
; The bar + fish sit inside the track, so this returns the FULL track even though
; the bar covers its middle. darkOnly = true counts just the dark-red track.
WidestReelSpan(x1, x2, y, maxGap, darkOnly := false) {
    bestL := 0
    bestR := -1
    bestW := -1
    curL := -1
    lastHit := -9999
    x := x1
    while (x <= x2) {
        c := GetPx(x, y)
        hit := darkOnly ? IsDarkRedPixel(c) : IsReelPixel(c)
        if (hit) {
            if (curL < 0)
                curL := x
            lastHit := x
        } else if (curL >= 0 && (x - lastHit) > maxGap) {
            if (lastHit - curL > bestW) {
                bestW := lastHit - curL
                bestL := curL
                bestR := lastHit
            }
            curL := -1
        }
        x += 1
    }
    if (curL >= 0 && (lastHit - curL) > bestW) {
        bestW := lastHit - curL
        bestL := curL
        bestR := lastHit
    }
    return { left: bestL, right: bestR, width: bestW }
}

; Count dark-red (track) pixels in a row range.
CountDarkRed(x1, x2, y) {
    if (x2 < x1)
        return 0
    n := 0
    x := x1
    while (x <= x2) {
        if IsDarkRedPixel(GetPx(x, y))
            n += 1
        x += 1
    }
    return n
}

; Pick the row within +-rowSpan of y that has the most reel pixels (1 px, step 2).
RefineBarRow(x1, x2, y, rowSpan) {
    bestY := y
    bestN := -1
    yy := Max(0, y - rowSpan)
    stop := Min(A_ScreenHeight - 1, y + rowSpan)
    while (yy <= stop) {
        n := 0
        xx := x1
        while (xx <= x2) {
            if IsReelPixel(GetPx(xx, yy))
                n += 1
            xx += 2
        }
        if (n > bestN) {
            bestN := n
            bestY := yy
        }
        yy += 1
    }
    return bestY
}

; Insertion sort: most bright-bar samples first, then most supporting reel pixels.
SortCandidates(arr) {
    i := 2
    while (i <= arr.Length) {
        cur := arr[i]
        j := i - 1
        while (j >= 1 && (arr[j].bars < cur.bars || (arr[j].bars = cur.bars && arr[j].track < cur.track))) {
            arr[j + 1] := arr[j]
            j -= 1
        }
        arr[j + 1] := cur
        i += 1
    }
    return arr
}

; Learn the most common bright-red (bar) and amber (fish) colours on a row.
LearnReelColors(x1, x2, y) {
    global REEL_TARGET_COLOR, REEL_PLAYER_COLOR
    barCounts := Map()
    fishCounts := Map()
    x := x1
    while (x <= x2) {
        c := GetPx(x, y)
        r := (c >> 16) & 0xFF
        g := (c >> 8) & 0xFF
        b := c & 0xFF
        if (r >= 130 && g <= 100 && b <= 100 && (r - g) >= 45 && (r - b) >= 45)
            BumpCount(barCounts, c)
        else if (r >= 175 && g >= 120 && b <= 150 && (r - b) >= 80)
            BumpCount(fishCounts, c)
        x += 1
    }
    if (barCounts.Count > 0)
        REEL_PLAYER_COLOR := MostCommonKey(barCounts)
    if (fishCounts.Count > 0)
        REEL_TARGET_COLOR := MostCommonKey(fishCounts)
}

CalibrateReelTarget() {
    global REEL_TARGET_COLOR, calibMsg, calibMode, calibStep
    MouseGetPos(&mx, &my)
    try REEL_TARGET_COLOR := PixelGetColor(mx, my, "RGB")
    calibMsg := "Reel target color saved (" Format("0x{:06X}", REEL_TARGET_COLOR) ")."
    calibMode := "", calibStep := 0
    SaveSettings()
    UpdateStatus()
}

CalibrateReelPlayer() {
    global REEL_PLAYER_COLOR, calibMsg, calibMode, calibStep
    MouseGetPos(&mx, &my)
    try REEL_PLAYER_COLOR := PixelGetColor(mx, my, "RGB")
    calibMsg := "Reel player color saved (" Format("0x{:06X}", REEL_PLAYER_COLOR) ")."
    calibMode := "", calibStep := 0
    SaveSettings()
    UpdateStatus()
}

ResetCalibration() {
    global SHAKE_X1 := 0, SHAKE_Y1 := 0, SHAKE_X2 := 0, SHAKE_Y2 := 0
    global SHAKE_CLICK_X := A_ScreenWidth // 2, SHAKE_CLICK_Y := A_ScreenHeight // 2
    global REEL_X1 := 0, REEL_X2 := 0, REEL_Y := 0
    global REEL_TARGET_COLOR := 0xF8B830, REEL_PLAYER_COLOR := 0xB82020
    global REEL_LOOKAHEAD_MS := 70, REEL_DEADZONE_PX := 6, REEL_DEADBAND_FRAC := 0.10
    global calibMode := "", calibStep := 0, calibMsg := "Calibration reset. Press F3 once on the reel bar."
    try FileDelete(CONFIG_PATH)
    SaveSettings()
    UpdateStatus()
}

ToggleMacro() {
    global macroOn, SHAKE_ENABLED, REEL_ENABLED, calibMsg
    global castPhase, castPhaseT, castTries, castPaused, castMsg, lastFishSeenT
    macroOn := !macroOn
    Dbg("F1 toggle -> " (macroOn ? "ON" : "OFF") " | reelConfigured=" ReelConfigured() " | geom=" REEL_X1 "-" REEL_X2 "@" REEL_Y)
    calibMsg := ""
    ; every ON/OFF starts the cast logic from scratch
    castPhase := "", castPhaseT := 0, castTries := 0, castPaused := false, castMsg := ""
    if (!macroOn) {
        ReleaseReel()
        ResetReelTracking()
        lastFishSeenT := 0
    } else {
        ResetReelTracking()
        lastFishSeenT := 0
        if (REEL_ENABLED && !ReelConfigured())
            calibMsg := "Reel not set: hover the reel bar and press F3 once."
    }
    UpdateStatus()
}

ShakeConfigured() {
    global SHAKE_X1, SHAKE_Y1, SHAKE_X2, SHAKE_Y2
    return !(SHAKE_X1 = 0 && SHAKE_Y1 = 0 && SHAKE_X2 = 0 && SHAKE_Y2 = 0)
}

ReelConfigured() {
    global REEL_X1, REEL_X2, REEL_Y
    return !(REEL_X1 = 0 && REEL_X2 = 0 && REEL_Y = 0)
}

UpdateStatus() {
    global macroOn, statusGui, statusText, SHAKE_ENABLED, REEL_ENABLED, calibMsg, reelDbg, SELFTEST_MODE
    global CAST_ENABLED, castMsg, lastFishSeenT, INPUT_MODE
    global OVERLAY_W, OVERLAY_H
    if (SELFTEST_MODE)
        return
    state := macroOn ? "ON" : "OFF"
    shake := (SHAKE_ENABLED ? "Shake:" (ShakeConfigured() ? "ready" : "set w/ F2") : "Shake:off")
    reel := (REEL_ENABLED ? "Reel:" (ReelConfigured() ? "ready" : "F3 once") : "Reel:off")
    cast := (CAST_ENABLED ? "Cast:auto" : "Cast:off")
    input := (INPUT_MODE = "event" ? "In:event" : "In:SendInput")
    hint := (calibMsg != "") ? calibMsg : "F1 on/off | F3 setup | F6/F8 predict | F9/F10 steady | F11 cast | F12 input | Esc quit"
    live := ""
    if (macroOn) {
        if (castMsg != "")
            live := "`n" castMsg
        else if (reelDbg != "")
            live := "`n" reelDbg
    }
    statusText.Value := "Fisch Helper: " state "  [" shake " | " reel " | " cast " | " input "]" live "`n" hint "`nVisual/supervised only - check Fisch/Roblox rules"
    statusGui.BackColor := macroOn ? "0C2416" : "14181C"
    try statusGui.Show("NoActivate w" OVERLAY_W " h" OVERLAY_H)
}

ScanLoop() {
    global macroOn, SHAKE_ENABLED, REEL_ENABLED
    if (!macroOn)
        return

    didReel := false
    if (REEL_ENABLED && ReelConfigured()) {
        didReel := TryReel()
    } else {
        ReleaseReel()
    }

    ; Avoid shake-clicking while actively controlling the reel bar.
    if (!didReel && SHAKE_ENABLED && ShakeConfigured()) {
        TryShake()
    }
}

TryShake() {
    global SHAKE_X1, SHAKE_Y1, SHAKE_X2, SHAKE_Y2
    global SHAKE_COLOR, SHAKE_VARIATION
    global SHAKE_CLICK_X, SHAKE_CLICK_Y
    global lastClickTime, CLICK_COOLDOWN_MS

    now := A_TickCount
    if (now - lastClickTime < CLICK_COOLDOWN_MS)
        return

    try {
        found := PixelSearch(&fx, &fy, SHAKE_X1, SHAKE_Y1, SHAKE_X2, SHAKE_Y2, SHAKE_COLOR, SHAKE_VARIATION)
    } catch {
        return
    }

    if (found) {
        ; Move first, then press - exactly what your hand does, so the click
        ; lands on the game window instead of wherever the cursor happens to be.
        MouseMove(SHAKE_CLICK_X, SHAKE_CLICK_Y, 0)
        MousePress(true)
        Sleep(40)
        MousePress(false)
        lastClickTime := A_TickCount
    }
}

; Read the reel bar + fish from the screen. No clicking, no state changes.
; Returns true only when BOTH the red bar and the amber fish are readable.
ReadReelBar(&bar, &fish) {
    global REEL_X1, REEL_X2, REEL_Y, REEL_STEP
    global REEL_TARGET_COLOR, REEL_TARGET_VARIATION
    global REEL_PLAYER_COLOR, REEL_PLAYER_VARIATION
    global REEL_BAR_MERGE_GAP, SCR

    bar := { found: false, left: 0, right: 0, center: 0, width: 0 }
    fish := { found: false, x: 0 }

    ; Copy this one screen row into memory (one fast BitBlt), then read pixels
    ; from memory. Without this, a 600-pixel scan can take seconds.
    SCR.Grab(REEL_X1, REEL_Y, REEL_X2 - REEL_X1 + 1, 1)

    ; The amber fish line is drawn ON TOP of the bright-red bar, which splits the bar
    ; into two pieces. FindBarSpan merges those pieces back into ONE bar span, so the
    ; bar center is correct (this was the cause of the left/right ping-pong).
    bar := FindBarSpan(REEL_X1, REEL_X2, REEL_Y, REEL_PLAYER_COLOR, REEL_PLAYER_VARIATION, REEL_STEP, REEL_BAR_MERGE_GAP)
    if (!bar.found)
        return false
    fish := FindFishX(REEL_X1, REEL_X2, REEL_Y, REEL_TARGET_COLOR, REEL_TARGET_VARIATION, REEL_STEP, bar.center)
    return fish.found
}

; One control tick: read the row and steer the bar. When the bar is gone (fish
; caught), the auto-cast logic takes over instead of clicking blindly.
TryReel() {
    global reelDbg, reelLastSeenT, castPhase
    now := A_TickCount
    bar := 0, fish := 0
    if (!ReadReelBar(&bar, &fish)) {
        if (reelLastSeenT != 0 && (now - reelLastSeenT) > 300)
            ResetReelTracking()
        if (castPhase = "") {
            reelDbg := "no reel bar on screen"
            ReleaseReel()
        }
        return CastTick(now)          ; true while casting, so shake stays off
    }
    return ControlReel(now, bar, fish)
}

ControlReel(now, bar, fish) {
    global REEL_X1, REEL_X2
    global REEL_HOLD_BIAS_PX
    global REEL_LOOKAHEAD_MS, REEL_BAR_LOOKAHEAD_MS
    global REEL_VEL_SMOOTHING, REEL_ACC_SMOOTHING, REEL_ACC_CLAMP, REEL_SWITCH_GUARD_PX
    global reelLastTargetX, reelLastTargetT, reelTargetVel, reelFishAcc
    global reelLastPlayerX, reelLastPlayerT, reelPlayerVel, reelPlayerAcc
    global reelLastSeenT, lastFishSeenT, reelLastSwitchT, reelDbg, reelHolding, reelDbgT
    global reelErr, reelBand
    global castPhase, castMsg, castTries, castPaused

    reelLastSeenT := now
    lastFishSeenT := now
    ; The fish is here, so any cast attempt is finished.
    castPhase := "", castMsg := "", castTries := 0, castPaused := false

    reelDbg := "bar " bar.width "px ctr " bar.center " | fish x" fish.x " | " (reelHolding ? "HOLD" : "release")

    ; --- fish velocity + acceleration (px per ms, px per ms^2) ---
    if (reelLastTargetX != "" && reelLastTargetT != 0) {
        dt := now - reelLastTargetT
        if (dt > 0 && dt <= 400) {
            instV := (fish.x - reelLastTargetX) / dt
            prevV := reelTargetVel
            reelTargetVel := reelTargetVel * (1 - REEL_VEL_SMOOTHING) + instV * REEL_VEL_SMOOTHING
            instA := (reelTargetVel - prevV) / dt
            reelFishAcc := reelFishAcc * (1 - REEL_ACC_SMOOTHING) + instA * REEL_ACC_SMOOTHING
            reelFishAcc := Max(-REEL_ACC_CLAMP, Min(REEL_ACC_CLAMP, reelFishAcc))
        } else {
            reelTargetVel := 0
            reelFishAcc := 0
        }
    }
    reelLastTargetX := fish.x
    reelLastTargetT := now

    ; --- bar velocity AND acceleration (the bar keeps drifting, and holding
    ;     changes how hard it drifts -> learn both instead of guessing) ---
    if (reelLastPlayerX != "" && reelLastPlayerT != 0) {
        dtp := now - reelLastPlayerT
        if (dtp > 0 && dtp <= 400) {
            instP := (bar.center - reelLastPlayerX) / dtp
            prevP := reelPlayerVel
            reelPlayerVel := reelPlayerVel * (1 - REEL_VEL_SMOOTHING) + instP * REEL_VEL_SMOOTHING
            instPA := (reelPlayerVel - prevP) / dtp
            reelPlayerAcc := reelPlayerAcc * (1 - REEL_ACC_SMOOTHING) + instPA * REEL_ACC_SMOOTHING
            reelPlayerAcc := Max(-REEL_ACC_CLAMP, Min(REEL_ACC_CLAMP, reelPlayerAcc))
        } else {
            reelPlayerVel := 0
            reelPlayerAcc := 0
        }
    }
    reelLastPlayerX := bar.center
    reelLastPlayerT := now

    ; --- predict the fish and the bar 65 ms ahead (quadratic = it knows how
    ;     hard the bar is accelerating, so it lets go early instead of
    ;     overshooting the fish) ---
    t := REEL_LOOKAHEAD_MS
    fishPred := fish.x + reelTargetVel * t + 0.5 * reelFishAcc * t * t
    fishPred := Max(REEL_X1, Min(REEL_X2, fishPred))
    tb := REEL_BAR_LOOKAHEAD_MS
    barPred := bar.center + reelPlayerVel * tb + 0.5 * reelPlayerAcc * tb * tb
    barPred := Max(REEL_X1, Min(REEL_X2, barPred))

    err := barPred - fishPred + REEL_HOLD_BIAS_PX
    guard := Max(0, REEL_SWITCH_GUARD_PX)
    reelErr := Round(err)
    reelBand := Round(guard)

    if (now - reelDbgT >= 500) {
        reelDbgT := now
        Dbg("reel bar=" bar.center " w=" bar.width " fish=" fish.x " fishPred=" Round(fishPred) " barPred=" Round(barPred)
            " fishAcc=" Round(reelFishAcc, 5) " barAcc=" Round(reelPlayerAcc, 5)
            " err=" Round(err) " guard=" Round(guard) " holding=" reelHolding)
    }

    ; Switch the instant the prediction says the bar would cross the fish.
    ; (The old code kept the current input inside a deadband, which meant it kept
    ; accelerating THROUGH the middle of the bar -> the overshoot.)
    ;   err < 0 -> bar predicted left of  fish -> holding pushes it right
    ;   err > 0 -> bar predicted right of fish -> releasing lets it drift left
    wantHold := (err < 0)
    if (wantHold == reelHolding)
        return true
    if (Abs(err) <= guard)
        return true                 ; too close to call: leave the input alone
    if (wantHold)
        HoldReel()
    else
        ReleaseReel()
    return true
}

; -----------------------------------------------------------------------------
; Auto-cast
;
; The reel bar only exists while a fish is on the line, so "bar gone" means the
; fish is caught (or the line broke). Wait CAST_GONE_MS to be sure it is not a
; one-frame flicker, hold the mouse for CAST_HOLD_MS to cast, release, then wait
; CAST_WAIT_MS for the fish to come back. No fish -> cast again.
;
; The very first cast is yours: auto-cast only starts once the reel bar has been
; seen at least once since the helper was switched on.
; -----------------------------------------------------------------------------
CastTick(now) {
    global CAST_ENABLED, CAST_HOLD_MS, CAST_WAIT_MS, CAST_GONE_MS, CAST_MAX_TRIES
    global castPhase, castPhaseT, castTries, castPaused, castMsg, lastFishSeenT

    if (!CAST_ENABLED || castPaused)
        return false

    if (castPhase = "hold") {
        if (now - castPhaseT >= CAST_HOLD_MS) {
            ReleaseReel()                       ; letting go performs the cast
            castPhase := "wait"
            castPhaseT := now
            castMsg := "cast " castTries " done - waiting " CAST_WAIT_MS " ms for the fish"
        }
        return true
    }

    if (castPhase = "wait") {
        if (now - castPhaseT >= CAST_WAIT_MS)
            return StartCast(now)               ; no fish -> cast again
        return true
    }

    ; idle: the fish must have been seen, and must stay gone for a moment
    if (lastFishSeenT = 0)
        return false
    if (now - lastFishSeenT < CAST_GONE_MS)
        return false
    return StartCast(now)
}

StartCast(now) {
    global CAST_HOLD_MS, CAST_MAX_TRIES
    global castPhase, castPhaseT, castTries, castPaused, castMsg

    castTries += 1
    if (castTries > CAST_MAX_TRIES) {
        castPaused := true
        castMsg := "auto-cast paused (no fish after " CAST_MAX_TRIES " casts) - press F11"
        return false
    }
    castPhase := "hold"
    castPhaseT := now
    castMsg := "casting " castTries ": holding the mouse " Round(CAST_HOLD_MS / 1000, 2) " s"
    HoldReel()
    return true
}

; ---------------------------------------------------------------------------
; Reel pixel matching
; ---------------------------------------------------------------------------

; Any reddish/amber pixel that belongs to the reel widget (used by F3 setup).
; NOTE: this must NOT match the game's brown wooden background (r~81,g~47,b~32)
; or other dim UI, which is why the dark-red branch requires very low g/b.
IsReelPixel(c) {
    if IsDarkRedPixel(c)                                                      ; dark-red track / blades
        return true
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    if (r >= 130 && g <= 100 && b <= 100 && (r - g) >= 45 && (r - b) >= 45)   ; bright-red control bar
        return true
    if (r >= 175 && g >= 120 && b <= 150 && (r - b) >= 80)                    ; amber fish
        return true
    return false
}

; Dark-red track / blade decoration pixel (g and b almost zero -> not the brown
; background and not the grey-black overlay).
IsDarkRedPixel(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return (r >= 25 && r <= 150 && g <= 26 && b <= 26)
}

; Bright control-bar pixel. The r/g/b gates keep the dark-red track and the
; amber fish from ever matching the bar, even if they are similar in color.
IsBarPixel(c, ref, variation) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    if (r < 130 || g > 105 || b > 105)
        return false
    if ((r - g) < 40 || (r - b) < 40)
        return false
    return ColorNear(c, ref, variation)
}

; Amber fish pixel.
IsFishPixel(c, ref, variation) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    if (r < 170 || g < 110 || b > 160)
        return false
    if ((r - b) < 70)
        return false
    return ColorNear(c, ref, variation)
}

; Walk one row and return matching runs as {left, right}.
; Pass ref = "" to match any pixel of that kind (used before the colours are known).
CollectRuns(x1, x2, y, kind, ref, variation, step) {
    if (x2 < x1) {
        tmp := x1
        x1 := x2
        x2 := tmp
    }
    segs := []
    inSeg := false
    segL := 0
    segR := 0
    lastHit := -9999
    x := x1
    while (x <= x2) {
        c := GetPx(x, y)
        if (ref = "")
            hit := (kind = "bar") ? IsBarPixel(c, c, 0) : IsFishPixel(c, c, 0)
        else
            hit := (kind = "bar") ? IsBarPixel(c, ref, variation) : IsFishPixel(c, ref, variation)
        if (hit) {
            if (!inSeg) {
                inSeg := true
                segL := x
            }
            segR := x
            lastHit := x
        } else if (inSeg && (x - lastHit) > Max(step * 2, 3)) {
            segs.Push({ left: segL, right: segR })
            inSeg := false
        }
        x += step
    }
    if (inSeg)
        segs.Push({ left: segL, right: segR })
    return segs
}

; Merge bright-red runs that are split by the amber fish line (gap <= mergeGap)
; and return the widest merged span = the control bar.
FindBarSpan(x1, x2, y, color, variation, step, mergeGap) {
    segs := CollectRuns(x1, x2, y, "bar", color, variation, step)
    if (segs.Length = 0)
        return { found: false, left: 0, right: 0, center: 0, width: 0 }

    bestL := 0
    bestR := 0
    bestW := -1
    curL := segs[1].left
    curR := segs[1].right
    i := 2
    while (i <= segs.Length) {
        if (segs[i].left - curR <= mergeGap) {
            curR := segs[i].right
        } else {
            if ((curR - curL) > bestW) {
                bestW := curR - curL
                bestL := curL
                bestR := curR
            }
            curL := segs[i].left
            curR := segs[i].right
        }
        i += 1
    }
    if ((curR - curL) > bestW) {
        bestW := curR - curL
        bestL := curL
        bestR := curR
    }
    if (bestW < 16)          ; too narrow to be the control bar
        return { found: false, left: 0, right: 0, center: 0, width: 0 }
    return { found: true, left: bestL, right: bestR, center: (bestL + bestR) // 2, width: bestW + 1 }
}

; Widest amber run on the row = the fish line. Ties go to the run nearest the bar.
FindFishX(x1, x2, y, color, variation, step, preferNear) {
    segs := CollectRuns(x1, x2, y, "fish", color, variation, step)
    best := ""
    bestScore := -999999
    for s in segs {
        w := s.right - s.left
        if (w < 2)          ; ignore tiny colour noise
            continue
        score := w
        if (preferNear != "")
            score += Max(0, 120 - Abs(((s.left + s.right) // 2) - preferNear)) / 2
        if (score > bestScore) {
            bestScore := score
            best := s
        }
    }
    if (best = "")
        return { found: false, x: 0, width: 0 }
    return { found: true, x: (best.left + best.right) // 2, width: best.right - best.left + 1 }
}

BumpCount(m, k) {
    m[k] := m.Has(k) ? m[k] + 1 : 1
}

MostCommonKey(m) {
    bestK := 0
    bestV := -1
    for k, v in m {
        if (v > bestV) {
            bestV := v
            bestK := k
        }
    }
    return bestK
}

ColorNear(c1, c2, variation) {
    r1 := (c1 >> 16) & 0xFF, g1 := (c1 >> 8) & 0xFF, b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF, g2 := (c2 >> 8) & 0xFF, b2 := c2 & 0xFF
    return (Abs(r1-r2) <= variation && Abs(g1-g2) <= variation && Abs(b1-b2) <= variation)
}

; Send a real left-button press/release through the OS input queue (SendInput),
; which is the same path a physical mouse click takes. F12 picks the legacy
; mouse_event API instead, for games that filter one of the two.
MousePress(down) {
    global INPUT_MODE, SELFTEST_MODE
    if (SELFTEST_MODE)
        return
    if (INPUT_MODE = "event") {
        ; MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004
        DllCall("user32\mouse_event", "UInt", down ? 0x0002 : 0x0004,
            "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    } else {
        Send(down ? "{LButton down}" : "{LButton up}")
    }
}

HoldReel() {
    global reelHolding, reelLastSwitchT
    if (!reelHolding) {
        MousePress(true)
        reelHolding := true
        reelLastSwitchT := A_TickCount
    }
}

ReleaseReel() {
    global reelHolding, reelLastSwitchT
    if (reelHolding) {
        MousePress(false)
        reelHolding := false
        reelLastSwitchT := A_TickCount
    }
}

; ---------------------------------------------------------------------------
; Self-test runner (only used with --selftest, see the top of the script).
; ---------------------------------------------------------------------------
RunSelfTest(dir) {
    global SELFTEST_MODE, SCR, REEL_X1, REEL_X2, REEL_Y
    global REEL_PLAYER_COLOR, REEL_TARGET_COLOR, calibMsg, reelDbg, reelHolding
    global reelErr, reelBand, SCAN_INTERVAL_MS
    global castPhase, castTries, castMsg

    SELFTEST_MODE := true
    out := "=== FischMacro selftest ===`n"
    out .= "screen " A_ScreenWidth "x" A_ScreenHeight "`n"

    first := dir "\frame_00.bgr"
    if (!SCR.LoadBGR(first, A_ScreenWidth, A_ScreenHeight)) {
        FileAppend(out "FAIL: cannot read " first "`n", A_ScriptDir "\selftest.out")
        ExitApp(1)
    }

    t0 := A_TickCount
    CalibrateReel()
    out .= ("calib ms=" (A_TickCount - t0)
        " track=" REEL_X1 "-" REEL_X2 "@" REEL_Y
        " barColor=" Format("0x{:06X}", REEL_PLAYER_COLOR)
        " fishColor=" Format("0x{:06X}", REEL_TARGET_COLOR)
        " configured=" (REEL_X1 > 0 ? 1 : 0) "`n")
    out .= "calib msg=" calibMsg "`n"

    i := 1
    while (i < 200) {
        path := Format("{}\frame_{:02d}.bgr", dir, i)
        if (!FileExist(path))
            break
        if (!SCR.LoadBGR(path, A_ScreenWidth, A_ScreenHeight)) {
            out .= "f" i ": cannot read frame`n"
            break
        }
        Sleep(SCAN_INTERVAL_MS)          ; mimic the real 30 ms control loop
        before := reelHolding
        TryReel()
        dec := "keep"
        if (reelHolding != before)
            dec := reelHolding ? "HOLD" : "release"
        out .= ("f" Format("{:02d}", i) " err=" reelErr " band=" reelBand " dec=" dec
            " cast=" (castPhase = "" ? "-" : castPhase) "/" castTries " | " (castMsg != "" ? castMsg : reelDbg) "`n")
        i += 1
    }

    FileAppend(out, A_ScriptDir "\selftest.out")
    ExitApp(0)
}
