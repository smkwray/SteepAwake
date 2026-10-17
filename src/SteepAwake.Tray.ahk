;@Ahk2Exe-SetMainIcon ..\assets\indefinite-dark.ico
;@Ahk2Exe-AddResource ..\assets\normal-dark.ico, 201
;@Ahk2Exe-AddResource ..\assets\timed-dark.ico, 202
;@Ahk2Exe-AddResource ..\assets\indefinite-dark.ico, 203
;@Ahk2Exe-AddResource ..\assets\normal-light.ico, 204
;@Ahk2Exe-AddResource ..\assets\timed-light.ico, 205
;@Ahk2Exe-AddResource ..\assets\indefinite-light.ico, 206
;@Ahk2Exe-SetCompanyName smkwray
;@Ahk2Exe-SetDescription Keep Windows awake from the tray
;@Ahk2Exe-SetFileVersion 0.2.1
;@Ahk2Exe-SetInternalName SteepAwake
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Shane Wray
;@Ahk2Exe-SetName SteepAwake
;@Ahk2Exe-SetOrigFilename SteepAwake.exe
;@Ahk2Exe-SetProductName SteepAwake
;@Ahk2Exe-SetProductVersion 0.2.1

#Requires AutoHotkey v2.0
#SingleInstance Off

Persistent

global AppName := "SteepAwake"
global StateDirectory := EnvGet("LOCALAPPDATA") "\SteepAwake"
global StateFile := StateDirectory "\state.ini"
global DeviceConfigFile := StateDirectory "\device.ini"
global StartupKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global StartupValueName := "SteepAwake"
global SessionActive := false
; Saved sleep, display and lid values for every power plan, keyed by plan GUID.
global SessionPlans := Map()
global SessionExpiry := ""
global SessionLabel := "Normal sleep"
global KeepDisplayOn := false
global KeepAwakeWithLidClosed := false
global PauseAsusOptimizationDuringSession := false
global EnableAsusOptimizationToggle := false
global AsusOptimizationServiceName := "ASUSOptimization"
global AsusOptimizationState := "unknown"
global AsusOptimizationPaused := false
global AsusOptimizationBeforeState := ""
global AsusOptimizationRestoreRequired := false
global AsusOptimizationPhase := "none"
global AsusOptimizationSessionId := ""
global AsusOptimizationLastError := ""
global AsusOptimizationTransitionActive := false
global TraySid := ""
global TrayMutexHandle := 0
global TrayReadyEventHandle := 0
global TrayShutdownEventHandle := 0
global TrayStoppedEventHandle := 0
global TrayAwakeEventHandle := 0
global TrayShuttingDown := false
global PowerRequestHandle := 0
; POWER_REQUEST_TYPE values from winnt.h.
global PowerRequestDisplayRequired := 0
global PowerRequestSystemRequired := 1
global ACRemovalGraceMs := 60000
global PowerRequestSystemActive := false
global PowerRequestDisplayActive := false
global PowerDisplayNotificationHandle := 0
global PowerSourceNotificationHandle := 0
global CurrentConsoleDisplayState := -1
global NodeProtectionFailureShown := false
global RestoreFailureNoticeShown := false
global LastIconKey := ""
global IconResources := Map(
    "normal-dark", 201,
    "timed-dark", 202,
    "indefinite-dark", 203,
    "normal-light", 204,
    "timed-light", 205,
    "indefinite-light", 206)

if HasArgument("--syntax-check")
    ExitApp(0)
if !A_IsAdmin
    ExitApp(10)
if !HasArgument("--task-entry")
    ExitApp(11)
if !AcquireTrayMutex()
    ExitApp(0)
CreateTrayControlEvents()
RemoveLegacyScheduledTasks()

DirCreate(StateDirectory)

LoadPreferences()
LoadDeviceConfig()
RefreshAsusOptimizationState()
BuildTrayMenu()
LoadSession()
SetTimer(CheckExpiration, 5000)
SetTimer(CheckTrayEvents, 250)
OnMessage(0x001A, HandleSettingChange)
OnExit(HandleExit)
OnMessage(0x0218, HandlePowerBroadcast)
RegisterPowerNotifications()
SignalTrayReady()

AcquireTrayMutex() {
    global TraySid, TrayMutexHandle

    TraySid := CurrentUserSid()
    name := "Local\SteepAwake.Tray.Mutex." TraySid
    handle := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 1,
        "WStr", name, "Ptr")
    if !handle
        throw Error("Windows could not create the SteepAwake tray mutex ("
            A_LastError ").")

    if DllCall("Kernel32\GetLastError", "UInt") = 183 {
        CloseTrayHandle(handle)
        return false
    }
    TrayMutexHandle := handle
    return true
}

CreateTrayControlEvents() {
    global TraySid
    global TrayReadyEventHandle, TrayShutdownEventHandle
    global TrayStoppedEventHandle, TrayAwakeEventHandle

    TrayReadyEventHandle := CreateTrayEvent(
        "Local\SteepAwake.Tray.Ready." TraySid)
    TrayShutdownEventHandle := CreateTrayEvent(
        "Local\SteepAwake.Tray.Shutdown." TraySid)
    TrayStoppedEventHandle := CreateTrayEvent(
        "Local\SteepAwake.Tray.Stopped." TraySid)
    ; The elevated token's default DACL omits the user, so grant the unelevated
    ; launcher the right to signal this event, as clicking the menu would.
    TrayAwakeEventHandle := CreateTrayEvent(
        "Local\SteepAwake.Tray.Awake." TraySid,
        "D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x100002;;;" TraySid ")")
    ResetTrayEvent(TrayReadyEventHandle)
    ResetTrayEvent(TrayShutdownEventHandle)
    ResetTrayEvent(TrayStoppedEventHandle)
    ResetTrayEvent(TrayAwakeEventHandle)
}

CreateTrayEvent(name, sddl := "") {
    attributes := 0
    descriptor := 0
    if sddl {
        if !DllCall("Advapi32\ConvertStringSecurityDescriptorToSecurityDescriptorW",
            "WStr", sddl, "UInt", 1, "Ptr*", &descriptor, "Ptr", 0)
            throw Error("Windows could not build a SteepAwake event descriptor ("
                A_LastError ").")
        attributes := Buffer(8 + 2 * A_PtrSize, 0)
        NumPut("UInt", attributes.Size, attributes, 0)
        NumPut("Ptr", descriptor, attributes, A_PtrSize)
    }
    try {
        handle := DllCall("Kernel32\CreateEventW", "Ptr", attributes, "Int", 1,
            "Int", 0, "WStr", name, "Ptr")
        if !handle
            throw Error("Windows could not create a SteepAwake control event ("
                A_LastError ").")
        return handle
    } finally {
        if descriptor
            DllCall("Kernel32\LocalFree", "Ptr", descriptor, "Ptr")
    }
}

ResetTrayEvent(handle) {
    if !DllCall("Kernel32\ResetEvent", "Ptr", handle)
        throw Error("Windows could not reset a SteepAwake control event ("
            A_LastError ").")
}

SignalTrayReady() {
    global TrayReadyEventHandle
    if !DllCall("Kernel32\SetEvent", "Ptr", TrayReadyEventHandle)
        throw Error("Windows could not signal SteepAwake readiness ("
            A_LastError ").")
}

CheckTrayEvents(*) {
    global TrayShutdownEventHandle, TrayAwakeEventHandle, TrayShuttingDown

    if TrayShuttingDown
        return
    if DllCall("Kernel32\WaitForSingleObject",
        "Ptr", TrayShutdownEventHandle, "UInt", 0, "UInt") = 0
        return ShutdownTray()
    ; `SteepAwake.exe --awake` starts an indefinite session, as the menu does.
    if DllCall("Kernel32\WaitForSingleObject",
        "Ptr", TrayAwakeEventHandle, "UInt", 0, "UInt") = 0 {
        ResetTrayEvent(TrayAwakeEventHandle)
        SelectIndefinitely()
    }
}

ShutdownTray() {
    global TrayShuttingDown
    global TrayStoppedEventHandle

    if TrayShuttingDown
        return
    TrayShuttingDown := true
    if !RestoreNormal(false) {
        TrayShuttingDown := false
        return
    }
    DllCall("Kernel32\SetEvent", "Ptr", TrayStoppedEventHandle)
    ExitApp()
}

CloseTrayHandle(handle) {
    if handle
        DllCall("Kernel32\CloseHandle", "Ptr", handle)
}

CurrentUserSid() {
    token := 0
    process := DllCall("Kernel32\GetCurrentProcess", "Ptr")
    if !DllCall("Advapi32\OpenProcessToken", "Ptr", process,
        "UInt", 0x0008, "Ptr*", &token)
        throw Error("Windows could not open the current user token ("
            A_LastError ").")

    try {
        sidBuffer := Buffer(1024, 0)
        size := sidBuffer.Size
        if !DllCall("Advapi32\GetTokenInformation", "Ptr", token,
            "Int", 1, "Ptr", sidBuffer.Ptr, "UInt", sidBuffer.Size,
            "UInt*", &size)
            throw Error("Windows could not read the current user SID ("
                A_LastError ").")

        sidTextPtr := 0
        if !DllCall("Advapi32\ConvertSidToStringSidW",
            "Ptr", NumGet(sidBuffer, 0, "Ptr"), "Ptr*", &sidTextPtr)
            throw Error("Windows could not format the current user SID ("
                A_LastError ").")
        try return StrGet(sidTextPtr)
        finally DllCall("Kernel32\LocalFree", "Ptr", sidTextPtr)
    } finally {
        CloseTrayHandle(token)
    }
}

RemoveLegacyScheduledTasks() {
    legacyNames := [
        "SteepAwake (Elevated)",
        "SteepAwake (ASUSOptimization Start)",
        "SteepAwake (ASUSOptimization Stop)"]
    try {
        scheduler := ComObject("Schedule.Service")
        scheduler.Connect()
        root := scheduler.GetFolder("\")
        for name in legacyNames
            try root.DeleteTask(name, 0)
    }
}

BuildTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Normal sleep", SelectNormal)
    A_TrayMenu.Add()
    A_TrayMenu.Add("30 minutes", Select30Minutes)
    A_TrayMenu.Add("1 hour", Select1Hour)
    A_TrayMenu.Add("2 hours", Select2Hours)
    A_TrayMenu.Add("4 hours", Select4Hours)
    A_TrayMenu.Add("6 hours", Select6Hours)
    A_TrayMenu.Add("Indefinitely", SelectIndefinitely)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Keep display active on AC while awake", ToggleKeepDisplayOn)
    A_TrayMenu.Add("Keep awake with lid closed", ToggleKeepAwakeWithLidClosed)
    if EnableAsusOptimizationToggle {
        A_TrayMenu.Add()
        A_TrayMenu.Add(
            "Pause ASUSOptimization during awake sessions",
            ToggleAsusOptimization)
    }
    A_TrayMenu.Add()
    A_TrayMenu.Add(StartupMenuLabel(), ToggleStartup)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", ExitTrayApp)
    A_TrayMenu.ClickCount := 1
    RefreshTray()
}

SelectNormal(*) {
    RestoreNormal(true)
}

Select30Minutes(*) {
    StartSession(30, "30 minutes")
}

Select1Hour(*) {
    StartSession(60, "1 hour")
}

Select2Hours(*) {
    StartSession(120, "2 hours")
}

Select4Hours(*) {
    StartSession(240, "4 hours")
}

Select6Hours(*) {
    StartSession(360, "6 hours")
}

SelectIndefinitely(*) {
    StartSession(0, "Indefinitely")
}

StartSession(minutes, label) {
    global SessionActive, SessionPlans
    global SessionExpiry, SessionLabel
    global AsusOptimizationSessionId, AsusOptimizationPhase
    global NodeProtectionFailureShown, RestoreFailureNoticeShown

    try {
        if SessionActive && AsusOptimizationPhase = "restore_failed"
            throw Error("The previous session still needs restoration.")
        if !SessionActive {
            if !IsAcPowerAvailable()
                throw Error("Awake sessions require AC power. Plug in the computer before starting one.")
            SessionPlans := Map()
            for plan in PowerSchemes()
                SessionPlans[plan] := ReadPowerValues(plan)
            AsusOptimizationSessionId := FormatTime(A_NowUTC, "yyyyMMddHHmmss")
                . "-" . A_TickCount
            AsusOptimizationPhase := "enter_prepared"
        }

        SessionActive := true
        NodeProtectionFailureShown := false
        RestoreFailureNoticeShown := false
        SessionExpiry := minutes ? DateAdd(A_Now, minutes, "Minutes") : ""
        SessionLabel := label
        SaveSession()
        AcquireNodePowerRequests()
        ApplyAsusOptimizationSessionPolicy()
        ApplySessionPolicy()
        AsusOptimizationPhase := PauseAsusOptimizationDuringSession
            ? "active" : "none"
        SaveSession()
        RefreshTray()

        message := minutes
            ? "Sleep disabled for " label "."
            : "Sleep disabled until you select Normal sleep."
        TrayTip(message, AppName, 1)
    } catch Error as err {
        try RestoreNormal(false)
        MsgBox("Could not activate " AppName ".`n`n" err.Message,
            AppName, "Iconx")
    }
}

RestoreNormal(showNotice := false) {
    global SessionActive, SessionPlans
    global SessionExpiry, SessionLabel
    global AsusOptimizationBeforeState, AsusOptimizationRestoreRequired
    global AsusOptimizationPhase, AsusOptimizationSessionId
    global AsusOptimizationLastError
    global RestoreFailureNoticeShown

    try {
        if SessionActive && SessionPlans.Count {
            existingPlans := Map()
            for plan in PowerSchemes()
                existingPlans[plan] := true
            for plan, normal in SessionPlans {
                ; A plan deleted during the session has nothing to restore.
                if !existingPlans.Has(plan)
                    continue
                SetSleepValues(plan, normal.AC, normal.DC)
                SetDisplayValues(plan, normal.DisplayAC, normal.DisplayDC)
                if normal.LidAC >= 0 && normal.LidDC >= 0
                    SetLidValues(plan, normal.LidAC, normal.LidDC)
            }
            ReapplyActiveScheme()
        }

        RestoreAsusOptimizationService()
        ReleaseNodePowerRequests()
    } catch Error as err {
        AsusOptimizationLastError := err.Message
        SaveSession()
        if !RestoreFailureNoticeShown {
            RestoreFailureNoticeShown := true
            detail := err.Message
            try {
                if err.HasProp("Line")
                    detail .= "`n`nSource line: " err.Line
            }
            if showNotice
                MsgBox("Could not restore the normal session state.`n`n"
                    detail, AppName, "Iconx")
            else
                TrayTip("Restore is pending: " detail, AppName, 2)
        }
        return false
    }

    SessionActive := false
    SessionPlans := Map()
    SessionExpiry := ""
    SessionLabel := "Normal sleep"
    AsusOptimizationBeforeState := ""
    AsusOptimizationRestoreRequired := false
    AsusOptimizationPhase := "none"
    AsusOptimizationSessionId := ""
    AsusOptimizationLastError := ""
    RestoreFailureNoticeShown := false
    SaveSession()
    RefreshTray()

    if showNotice
        TrayTip("The normal Windows sleep policy is active.", AppName, 1)
    return true
}

CheckExpiration() {
    global SessionActive, SessionExpiry

    if SessionActive {
        try {
            CoverActivePlan()
        } catch Error as err {
            TrayTip("The awake session is ending: " err.Message, AppName, 2)
            return RestoreNormal(true)
        }
    }

    if SessionActive && SessionExpiry {
        if DateDiff(SessionExpiry, A_Now, "Seconds") <= 0 {
            RestoreNormal(true)
        } else {
            RefreshTray()
        }
    }

    RefreshStartupCheck()
}

HandlePowerBroadcast(wParam, lParam, msg, hwnd) {
    global AppName, SessionActive, CurrentConsoleDisplayState
    global NodeProtectionFailureShown, PowerRequestDisplayActive
    global ACRemovalGraceMs

    if wParam != 0x8013 || !lParam
        return

    dataLength := NumGet(lParam, 16, "UInt")
    if dataLength < 1
        return

    if PowerSettingGuidMatches(lParam,
        "{6fe69556-704a-47a0-8f24-c28d936fda47}") {
        state := NumGet(lParam, 20, "UChar")
        CurrentConsoleDisplayState := state
        if SessionActive && PowerRequestDisplayActive && state = 0
            && !NodeProtectionFailureShown {
            NodeProtectionFailureShown := true
            TrayTip("Display protection was lost. The awake session is ending; another program's monitor-off command may have caused it.",
                AppName, 2)
            SetTimer(EndSessionAfterDisplayLoss, -1)
        }
        return
    }

    ; GUID_ACDC_POWER_SOURCE reports 0 for AC, 1 for battery, 2 for UPS.
    ; Chargers on some devices drop out for a few seconds while the battery
    ; sits at its charge limit, so recheck after a grace period instead of
    ; ending the session on the transient notification.
    if PowerSettingGuidMatches(lParam,
        "{5d3e9a59-e9d5-4b00-a6bd-ff34ff516bba}") {
        powerSource := NumGet(lParam, 20, "UChar")
        if SessionActive && powerSource != 0
            SetTimer(EndSessionAfterACRemoval, -ACRemovalGraceMs)
    }
}

EndSessionAfterDisplayLoss(*) {
    global AppName, SessionActive

    if SessionActive && RestoreNormal(false)
        TrayTip("Display protection was lost, so the awake session ended.",
            AppName, 2)
}

EndSessionAfterACRemoval(*) {
    global AppName, SessionActive

    if !SessionActive || IsAcPowerAvailable()
        return
    if RestoreNormal(false)
        TrayTip("AC power was removed, so the awake session ended.",
            AppName, 2)
}

RegisterPowerNotifications() {
    global PowerDisplayNotificationHandle, PowerSourceNotificationHandle

    displayGuid := GuidBuffer(
        "{6fe69556-704a-47a0-8f24-c28d936fda47}")
    sourceGuid := GuidBuffer(
        "{5d3e9a59-e9d5-4b00-a6bd-ff34ff516bba}")
    displayHandle := DllCall("User32\RegisterPowerSettingNotification",
        "Ptr", A_ScriptHwnd, "Ptr", displayGuid.Ptr, "UInt", 0, "Ptr")
    if !displayHandle
        throw Error("Windows could not register display-state notifications ("
            A_LastError ").")
    PowerDisplayNotificationHandle := displayHandle

    try {
        sourceHandle := DllCall(
            "User32\RegisterPowerSettingNotification",
            "Ptr", A_ScriptHwnd, "Ptr", sourceGuid.Ptr, "UInt", 0, "Ptr")
        if !sourceHandle
            throw Error("Windows could not register AC/DC notifications ("
                A_LastError ").")
        PowerSourceNotificationHandle := sourceHandle
    } catch Error as err {
        UnregisterPowerNotifications()
        throw err
    }
}

UnregisterPowerNotifications() {
    global PowerDisplayNotificationHandle, PowerSourceNotificationHandle

    if PowerDisplayNotificationHandle {
        DllCall("User32\UnregisterPowerSettingNotification",
            "Ptr", PowerDisplayNotificationHandle)
        PowerDisplayNotificationHandle := 0
    }
    if PowerSourceNotificationHandle {
        DllCall("User32\UnregisterPowerSettingNotification",
            "Ptr", PowerSourceNotificationHandle)
        PowerSourceNotificationHandle := 0
    }
}

AcquireNodePowerRequests() {
    global KeepDisplayOn, PowerRequestHandle, PowerRequestSystemActive
    global PowerRequestDisplayActive
    global PowerRequestDisplayRequired, PowerRequestSystemRequired

    if PowerRequestHandle
        return
    if !IsAcPowerAvailable()
        throw Error("AC power was removed before awake protection could start.")

    reasonText := "SteepAwake awake session"
    reasonContext := Buffer(8 + A_PtrSize, 0)
    NumPut("UInt", 0, reasonContext, 0)
    NumPut("UInt", 1, reasonContext, 4)
    NumPut("Ptr", StrPtr(reasonText), reasonContext, 8)

    PowerRequestHandle := DllCall("Kernel32\PowerCreateRequest",
        "Ptr", reasonContext.Ptr, "Ptr")
    if !PowerRequestHandle || PowerRequestHandle = -1
        throw Error("Windows could not create the awake power request ("
            A_LastError ").")

    try {
        if !DllCall("Kernel32\PowerSetRequest", "Ptr", PowerRequestHandle,
            "Int", PowerRequestSystemRequired, "Int")
            throw Error("Windows could not set the system-required power request ("
                A_LastError ").")
        PowerRequestSystemActive := true

        if KeepDisplayOn {
            if !DllCall("Kernel32\PowerSetRequest", "Ptr", PowerRequestHandle,
                "Int", PowerRequestDisplayRequired, "Int")
                throw Error("Windows could not set the display-required power request ("
                    A_LastError ").")
            PowerRequestDisplayActive := true
        }
    } catch Error as err {
        ReleaseNodePowerRequests()
        throw err
    }
}

SetNodeDisplayRequest(enabled) {
    global PowerRequestHandle, PowerRequestDisplayActive
    global PowerRequestDisplayRequired

    if !PowerRequestHandle
        throw Error("The awake power request is not active.")
    if enabled = PowerRequestDisplayActive
        return

    if enabled {
        if !DllCall("Kernel32\PowerSetRequest", "Ptr", PowerRequestHandle,
            "Int", PowerRequestDisplayRequired, "Int")
            throw Error("Windows could not enable display protection ("
                A_LastError ").")
        PowerRequestDisplayActive := true
    } else {
        if !DllCall("Kernel32\PowerClearRequest", "Ptr", PowerRequestHandle,
            "Int", PowerRequestDisplayRequired, "Int")
            throw Error("Windows could not disable display protection ("
                A_LastError ").")
        PowerRequestDisplayActive := false
    }
}

ReleaseNodePowerRequests() {
    global PowerRequestHandle, PowerRequestSystemActive
    global PowerRequestDisplayActive

    if !PowerRequestHandle
        return

    ; Closing the request handle releases all request types owned by it. Keep
    ; final restore independent of PowerClearRequest so Normal sleep and Exit
    ; cannot be trapped by a cleanup call after the policy is restored.
    DllCall("Kernel32\CloseHandle", "Ptr", PowerRequestHandle)
    PowerRequestHandle := 0
    PowerRequestSystemActive := false
    PowerRequestDisplayActive := false
}

IsAcPowerAvailable() {
    status := Buffer(12, 0)
    if !DllCall("Kernel32\GetSystemPowerStatus", "Ptr", status.Ptr, "Int")
        throw Error("Windows could not report the current AC/DC power source ("
            A_LastError ").")
    return NumGet(status, 0, "UChar") = 1
}

PowerSettingGuidMatches(settingPtr, expectedGuid) {
    textBuffer := Buffer(78, 0)
    if !DllCall("Ole32\StringFromGUID2", "Ptr", settingPtr,
        "Ptr", textBuffer.Ptr, "Int", 39, "Int")
        return false
    return StrLower(StrGet(textBuffer, "UTF-16")) = StrLower(expectedGuid)
}

; Every plan is overridden at session start, but a plan created during the
; session is not, so cover it as soon as it becomes active.
CoverActivePlan() {
    global SessionPlans

    plan := GetActiveScheme()
    if SessionPlans.Has(plan)
        return
    SessionPlans[plan] := ReadPowerValues(plan)
    SaveSession()
    ApplySessionPolicy()
}

LoadSession() {
    global SessionActive, SessionPlans
    global SessionExpiry, SessionLabel
    global AsusOptimizationBeforeState, AsusOptimizationRestoreRequired
    global AsusOptimizationPhase, AsusOptimizationSessionId
    global AsusOptimizationLastError

    SessionActive := Integer(IniRead(StateFile, "Session", "Active", "0")) = 1
    SessionPlans := Map()
    try {
        planLines := IniRead(StateFile, "Plans")
    } catch {
        planLines := ""
    }
    loop parse planLines, "`n", "`r" {
        separator := InStr(A_LoopField, "=")
        if !separator
            continue
        values := StrSplit(SubStr(A_LoopField, separator + 1), ",")
        if values.Length != 6
            continue
        SessionPlans[SubStr(A_LoopField, 1, separator - 1)] := {
            AC: Integer(values[1]), DC: Integer(values[2]),
            DisplayAC: Integer(values[3]), DisplayDC: Integer(values[4]),
            LidAC: Integer(values[5]), LidDC: Integer(values[6])}
    }
    SessionExpiry := IniRead(StateFile, "Session", "Expiry", "")
    SessionLabel := IniRead(StateFile, "Session", "Label", "Indefinitely")
    AsusOptimizationBeforeState := IniRead(
        StateFile, "Session", "AsusBeforeState", "")
    AsusOptimizationRestoreRequired := Integer(IniRead(
        StateFile, "Session", "AsusRestoreRequired", "0")) = 1
    AsusOptimizationPhase := IniRead(
        StateFile, "Session", "AsusPhase", "none")
    AsusOptimizationSessionId := IniRead(
        StateFile, "Session", "AsusSessionId", "")
    AsusOptimizationLastError := IniRead(
        StateFile, "Session", "AsusLastError", "")

    if !SessionActive {
        if AsusOptimizationRestoreRequired {
            try {
                RestoreAsusOptimizationService()
                ClearAsusOptimizationOwnership()
                SaveSession()
            } catch Error as err {
                MsgBox("Could not recover ASUSOptimization.`n`n" err.Message,
                    AppName, "Iconx")
            }
        }
        RefreshTray()
        return
    }

    ; An interrupted session recovers to Normal sleep rather than resuming.
    if !RestoreNormal(false)
        MsgBox("The interrupted " AppName " session still needs recovery.",
            AppName, "Iconx")
}

SaveSession() {
    global SessionActive, SessionPlans
    global SessionExpiry, SessionLabel
    global AsusOptimizationBeforeState, AsusOptimizationRestoreRequired
    global AsusOptimizationPhase, AsusOptimizationSessionId
    global AsusOptimizationLastError

    tempFile := StateFile ".tmp"
    try {
        if FileExist(tempFile)
            FileDelete(tempFile)
        if FileExist(StateFile)
            FileCopy(StateFile, tempFile, true)
        else
            FileAppend("", tempFile)

        ; Rewrite both sections whole so keys from older versions and plans
        ; from an earlier session cannot linger.
        try IniDelete(tempFile, "Session")
        try IniDelete(tempFile, "Plans")
        IniWrite(SessionActive ? 1 : 0, tempFile, "Session", "Active")
        for plan, normal in SessionPlans
            IniWrite(Format("{},{},{},{},{},{}", normal.AC, normal.DC,
                normal.DisplayAC, normal.DisplayDC, normal.LidAC, normal.LidDC),
                tempFile, "Plans", plan)
        IniWrite(SessionExpiry, tempFile, "Session", "Expiry")
        IniWrite(SessionLabel, tempFile, "Session", "Label")
        IniWrite(AsusOptimizationBeforeState,
            tempFile, "Session", "AsusBeforeState")
        IniWrite(AsusOptimizationRestoreRequired ? 1 : 0,
            tempFile, "Session", "AsusRestoreRequired")
        IniWrite(AsusOptimizationPhase, tempFile, "Session", "AsusPhase")
        IniWrite(AsusOptimizationSessionId,
            tempFile, "Session", "AsusSessionId")
        IniWrite(AsusOptimizationLastError,
            tempFile, "Session", "AsusLastError")
        FileMove(tempFile, StateFile, true)
    } catch Error as err {
        try FileDelete(tempFile)
        throw err
    }
}

RefreshTray() {
    global SessionActive, SessionLabel, SessionExpiry

    for item in ["Normal sleep", "30 minutes", "1 hour", "2 hours",
        "4 hours", "6 hours", "Indefinitely"]
        try A_TrayMenu.Uncheck(item)

    selected := SessionActive ? SessionLabel : "Normal sleep"
    try A_TrayMenu.Check(selected)
    RefreshOptionChecks()
    RefreshStartupCheck()

    if SessionActive {
        A_TrayMenu.Default := "Normal sleep"
        if SessionExpiry {
            secondsRemaining := Max(0, DateDiff(SessionExpiry, A_Now, "Seconds"))
            hoursRemaining := Floor(secondsRemaining / 3600)
            minutesRemaining := Max(1, Ceil(Mod(secondsRemaining, 3600) / 60))
            remainingText := hoursRemaining
                ? hoursRemaining "h " minutesRemaining "m"
                : minutesRemaining "m"
            A_IconTip := "AWAKE - " remainingText " remaining"
            SetTrayIcon("timed")
        } else {
            A_IconTip := "AWAKE INDEFINITELY"
            SetTrayIcon("indefinite")
        }
    } else {
        A_IconTip := "NORMAL SLEEP"
        A_TrayMenu.Default := "Indefinitely"
        SetTrayIcon("normal")
    }
}

SetTrayIcon(state) {
    global LastIconKey, IconResources

    lightTheme := 0
    try lightTheme := RegRead(
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        "SystemUsesLightTheme")
    key := state "-" (lightTheme ? "light" : "dark")
    if key = LastIconKey
        return

    if A_IsCompiled {
        TraySetIcon(A_ScriptFullPath, -IconResources[key], true)
    } else {
        TraySetIcon(A_ScriptDir "\..\assets\" key ".ico")
    }
    LastIconKey := key
}

HandleSettingChange(*) {
    global LastIconKey
    LastIconKey := ""
    RefreshTray()
}

LoadPreferences() {
    global KeepDisplayOn, KeepAwakeWithLidClosed
    global PauseAsusOptimizationDuringSession

    KeepDisplayOn := Integer(IniRead(
        StateFile, "Preferences", "KeepDisplayOn", "0")) = 1
    KeepAwakeWithLidClosed := Integer(IniRead(
        StateFile, "Preferences", "KeepAwakeWithLidClosed", "0")) = 1
    PauseAsusOptimizationDuringSession := Integer(IniRead(
        StateFile, "Preferences", "PauseAsusOptimization", "0")) = 1
}

LoadDeviceConfig() {
    global EnableAsusOptimizationToggle

    EnableAsusOptimizationToggle := Integer(IniRead(
        DeviceConfigFile, "Device", "EnableAsusOptimizationToggle", "0")) = 1
}

SavePreferences() {
    global PauseAsusOptimizationDuringSession

    IniWrite(KeepDisplayOn ? 1 : 0,
        StateFile, "Preferences", "KeepDisplayOn")
    IniWrite(KeepAwakeWithLidClosed ? 1 : 0,
        StateFile, "Preferences", "KeepAwakeWithLidClosed")
    IniWrite(PauseAsusOptimizationDuringSession ? 1 : 0,
        StateFile, "Preferences", "PauseAsusOptimization")
}

ToggleKeepDisplayOn(*) {
    global KeepDisplayOn, SessionActive, SessionPlans

    try {
        enabled := !KeepDisplayOn
        if SessionActive {
            for plan, normal in SessionPlans
                SetDisplayValues(plan, enabled ? 0 : normal.DisplayAC,
                    normal.DisplayDC)
            ReapplyActiveScheme()
            SetNodeDisplayRequest(enabled)
        }
        KeepDisplayOn := enabled
        SavePreferences()
        RefreshOptionChecks()
        TrayTip(enabled
            ? "The display will stay on during awake sessions."
            : "Normal display timeout will be used.",
            AppName, 1)
    } catch Error as err {
        MsgBox("Could not change the display option.`n`n" err.Message,
            AppName, "Iconx")
    }
}

ToggleKeepAwakeWithLidClosed(*) {
    global KeepAwakeWithLidClosed, SessionActive, SessionPlans

    try {
        enabled := !KeepAwakeWithLidClosed
        if enabled && !SessionActive {
            values := ReadPowerValues(GetActiveScheme())
            if values.LidAC < 0 || values.LidDC < 0
                throw Error("This computer does not expose a lid-close setting.")
        }
        if SessionActive {
            for plan, normal in SessionPlans {
                if normal.LidAC < 0 || normal.LidDC < 0
                    throw Error("This computer does not expose a lid-close setting.")
                if enabled
                    SetLidValues(plan, 0, 0)
                else
                    SetLidValues(plan, normal.LidAC, normal.LidDC)
            }
            ReapplyActiveScheme()
        }
        KeepAwakeWithLidClosed := enabled
        SavePreferences()
        RefreshOptionChecks()
        TrayTip(enabled
            ? "Lid close will not sleep Windows during awake sessions. Keep vents clear."
            : "Normal lid-close behavior will be used.",
            AppName, 1)
    } catch Error as err {
        MsgBox("Could not change the lid-close option.`n`n" err.Message,
            AppName, "Iconx")
    }
}

RefreshOptionChecks() {
    global KeepDisplayOn, SessionActive

    if KeepDisplayOn {
        try A_TrayMenu.Check("Keep display active on AC while awake")
    } else {
        try A_TrayMenu.Uncheck("Keep display active on AC while awake")
    }
    try A_TrayMenu.Enable("Keep display active on AC while awake")

    if KeepAwakeWithLidClosed {
        try A_TrayMenu.Check("Keep awake with lid closed")
    } else {
        try A_TrayMenu.Uncheck("Keep awake with lid closed")
    }

    if EnableAsusOptimizationToggle {
        if PauseAsusOptimizationDuringSession {
            try A_TrayMenu.Check(
                "Pause ASUSOptimization during awake sessions")
        } else {
            try A_TrayMenu.Uncheck(
                "Pause ASUSOptimization during awake sessions")
        }
    }
}

ToggleAsusOptimization(*) {
    global PauseAsusOptimizationDuringSession
    global SessionActive

    previous := PauseAsusOptimizationDuringSession
    PauseAsusOptimizationDuringSession := !previous
    try {
        SavePreferences()
        if SessionActive {
            if PauseAsusOptimizationDuringSession {
                ApplyAsusOptimizationSessionPolicy()
            } else {
                RestoreAsusOptimizationService()
                ClearAsusOptimizationOwnership()
                SaveSession()
            }
        }
        RefreshAsusOptimizationState()
        RefreshOptionChecks()
        TrayTip(PauseAsusOptimizationDuringSession
            ? "ASUSOptimization will be paused for awake sessions."
            : "ASUSOptimization will be restored when awake sessions end.",
            AppName, 1)
    } catch Error as err {
        PauseAsusOptimizationDuringSession := previous
        try SavePreferences()
        RefreshOptionChecks()
        MsgBox("Could not change ASUSOptimization.`n`n" err.Message,
            AppName, "Iconx")
    }
}

ApplyAsusOptimizationSessionPolicy() {
    global SessionActive, PauseAsusOptimizationDuringSession
    global AsusOptimizationBeforeState, AsusOptimizationRestoreRequired
    global AsusOptimizationPhase, AsusOptimizationLastError
    global AsusOptimizationTransitionActive

    if !SessionActive || !PauseAsusOptimizationDuringSession
        return
    if AsusOptimizationRestoreRequired || AsusOptimizationPhase = "active"
        return
    if AsusOptimizationTransitionActive
        throw Error("Another ASUSOptimization transition is already running.")

    state := WaitForAsusOptimizationState("", 30000)
    AsusOptimizationBeforeState := state
    AsusOptimizationRestoreRequired := state = "running"
    AsusOptimizationPhase := state = "running"
        ? "stop_pending" : "active"
    AsusOptimizationLastError := ""
    SaveSession()

    if state = "stopped"
        return

    AsusOptimizationTransitionActive := true
    try {
        RunAsusOptimizationCommand("stop")
        WaitForAsusOptimizationState("stopped", 30000)
        AsusOptimizationPhase := "active"
        SaveSession()
    } catch Error as err {
        AsusOptimizationPhase := "restore_failed"
        AsusOptimizationLastError := err.Message
        SaveSession()
        throw err
    } finally {
        AsusOptimizationTransitionActive := false
    }
}

RestoreAsusOptimizationService() {
    global AsusOptimizationRestoreRequired, AsusOptimizationPhase
    global AsusOptimizationLastError, AsusOptimizationTransitionActive

    if !AsusOptimizationRestoreRequired
        return
    if AsusOptimizationTransitionActive
        throw Error("Another ASUSOptimization transition is already running.")

    AsusOptimizationPhase := "restore_pending"
    AsusOptimizationLastError := ""
    SaveSession()
    AsusOptimizationTransitionActive := true
    try {
        state := WaitForAsusOptimizationState("", 30000)
        if state != "running" {
            RunAsusOptimizationCommand("start")
            WaitForAsusOptimizationState("running", 30000)
        }
        AsusOptimizationPhase := "active"
        SaveSession()
    } catch Error as err {
        AsusOptimizationPhase := "restore_failed"
        AsusOptimizationLastError := err.Message
        SaveSession()
        throw err
    } finally {
        AsusOptimizationTransitionActive := false
    }
}

ClearAsusOptimizationOwnership() {
    global AsusOptimizationBeforeState, AsusOptimizationRestoreRequired
    global AsusOptimizationPhase, AsusOptimizationSessionId
    global AsusOptimizationLastError

    AsusOptimizationBeforeState := ""
    AsusOptimizationRestoreRequired := false
    AsusOptimizationPhase := "none"
    AsusOptimizationSessionId := ""
    AsusOptimizationLastError := ""
}

WaitForAsusOptimizationState(expected, timeoutMs) {
    started := A_TickCount
    loop {
        state := QueryAsusOptimizationState()
        if expected = "" {
            if state = "running" || state = "stopped"
                return state
        } else if state = expected {
            return state
        }

        if A_TickCount - started >= timeoutMs
            throw Error("ASUSOptimization did not reach the expected state ("
                (expected = "" ? "running or stopped" : expected)
                "; last state: " state ").")
        Sleep(250)
    }
}

RefreshAsusOptimizationState() {
    global EnableAsusOptimizationToggle
    global AsusOptimizationState, AsusOptimizationPaused

    if !EnableAsusOptimizationToggle
        return

    try {
        AsusOptimizationState := QueryAsusOptimizationState()
        AsusOptimizationPaused := AsusOptimizationState = "stopped"
    } catch {
        AsusOptimizationState := "unknown"
        AsusOptimizationPaused := false
    }
}

QueryAsusOptimizationState() {
    global AsusOptimizationServiceName

    scm := DllCall("Advapi32\OpenSCManagerW",
        "Ptr", 0, "Ptr", 0, "UInt", 0x0001, "Ptr")
    if !scm
        throw Error("Windows could not open the Service Control Manager ("
            A_LastError ").")

    try {
        service := DllCall("Advapi32\OpenServiceW",
            "Ptr", scm, "WStr", AsusOptimizationServiceName,
            "UInt", 0x0004, "Ptr")
        if !service
            throw Error("Windows could not query ASUSOptimization ("
                A_LastError ").")

        try {
            status := Buffer(36, 0)
            bytesNeeded := 0
            result := DllCall("Advapi32\QueryServiceStatusEx",
                "Ptr", service, "Int", 0, "Ptr", status.Ptr,
                "UInt", status.Size, "UInt*", &bytesNeeded, "UInt")
            if !result
                throw Error("Windows could not read the ASUSOptimization state ("
                    A_LastError ").")

            state := NumGet(status, 4, "UInt")
            return state = 4 ? "running" : state = 1 ? "stopped" : "pending"
        } finally {
            DllCall("Advapi32\CloseServiceHandle", "Ptr", service)
        }
    } finally {
        DllCall("Advapi32\CloseServiceHandle", "Ptr", scm)
    }
}

RunAsusOptimizationCommand(action) {
    global AsusOptimizationServiceName

    if action != "start" && action != "stop"
        throw Error("Unknown ASUSOptimization action: " action)

    scm := DllCall("Advapi32\OpenSCManagerW",
        "Ptr", 0, "Ptr", 0, "UInt", 0x0001, "Ptr")
    if !scm
        throw Error("Windows could not open the Service Control Manager ("
            A_LastError ").")

    try {
        access := 0x0004 | (action = "start" ? 0x0010 : 0x0020)
        service := DllCall("Advapi32\OpenServiceW",
            "Ptr", scm, "WStr", AsusOptimizationServiceName,
            "UInt", access, "Ptr")
        if !service
            throw Error("Windows could not open ASUSOptimization for " action
                " (" A_LastError ").")

        try {
            if action = "start" {
                if !DllCall("Advapi32\StartServiceW",
                    "Ptr", service, "UInt", 0, "Ptr", 0)
                    && A_LastError != 1056
                    throw Error("Windows could not start ASUSOptimization ("
                        A_LastError ").")
            } else {
                status := Buffer(36, 0)
                if !DllCall("Advapi32\ControlService",
                    "Ptr", service, "UInt", 1, "Ptr", status)
                    && A_LastError != 1062
                    throw Error("Windows could not stop ASUSOptimization ("
                        A_LastError ").")
            }
        } finally {
            DllCall("Advapi32\CloseServiceHandle", "Ptr", service)
        }
    } finally {
        DllCall("Advapi32\CloseServiceHandle", "Ptr", scm)
    }
}

ToggleStartup(*) {
    try {
        if IsStartupEnabled() {
            RegDelete(StartupKey, StartupValueName)
            TrayTip("Automatic startup is off.", AppName, 1)
        } else {
            RegWrite(StartupCommand(), "REG_SZ", StartupKey, StartupValueName)
            TrayTip("Automatic startup is on.", AppName, 1)
        }
        RefreshStartupCheck()
    } catch Error as err {
        MsgBox("Could not change automatic startup.`n`n" err.Message,
            AppName, "Iconx")
    }
}

StartupMenuLabel() {
    return "Start with Windows"
}

RefreshStartupCheck() {
    label := StartupMenuLabel()
    enabled := IsStartupEnabled()
    if enabled {
        try A_TrayMenu.Check(label)
    } else {
        try A_TrayMenu.Uncheck(label)
    }
}

IsStartupEnabled() {
    try {
        return RegRead(StartupKey, StartupValueName) != ""
    } catch {
        return false
    }
}

StartupCommand() {
    launcher := A_IsCompiled
        ? A_ScriptDir "\SteepAwake.exe"
        : A_ScriptDir "\SteepAwake.Launcher.ahk"
    if A_IsCompiled
        return '"' launcher '"'
    return '"' A_AhkPath '" "' launcher '"'
}

HasArgument(expected) {
    for argument in A_Args
        if StrLower(argument) = StrLower(expected)
            return true
    return false
}

ReadPowerValues(plan) {
    schemeGuid := GuidBuffer(plan)
    sleepGroupGuid := GuidBuffer("{238c9fa8-0aad-41ed-83f4-97be242c8f20}")
    sleepSettingGuid := GuidBuffer("{29f6c1db-86da-48c5-9fdb-f2b67b1f44da}")
    displayGroupGuid := GuidBuffer("{7516b95f-f776-4464-8c53-06167f40cc99}")
    displaySettingGuid := GuidBuffer("{3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e}")
    lidGroupGuid := GuidBuffer("{4f971e89-eebd-4455-a8de-9e59040e7347}")
    lidSettingGuid := GuidBuffer("{5ca83367-6e45-459f-a27b-476b1d01c936}")

    lidAC := -1
    lidDC := -1
    try {
        lidAC := ReadPowerValue("PowerReadACValueIndex", schemeGuid,
            lidGroupGuid, lidSettingGuid)
        lidDC := ReadPowerValue("PowerReadDCValueIndex", schemeGuid,
            lidGroupGuid, lidSettingGuid)
    } catch {
    }

    return {
        AC: ReadPowerValue("PowerReadACValueIndex", schemeGuid,
            sleepGroupGuid, sleepSettingGuid),
        DC: ReadPowerValue("PowerReadDCValueIndex", schemeGuid,
            sleepGroupGuid, sleepSettingGuid),
        DisplayAC: ReadPowerValue("PowerReadACValueIndex", schemeGuid,
            displayGroupGuid, displaySettingGuid),
        DisplayDC: ReadPowerValue("PowerReadDCValueIndex", schemeGuid,
            displayGroupGuid, displaySettingGuid),
        LidAC: lidAC,
        LidDC: lidDC
    }
}

ApplySessionPolicy() {
    global KeepDisplayOn, KeepAwakeWithLidClosed, SessionPlans

    ; Armoury Crate switches the active plan on its own, including the moment
    ; AC drops out, and Windows applies the new plan's lid action at once.
    ; Override every plan so a switch cannot disarm the session.
    for plan, normal in SessionPlans {
        ; Power requests are the primary protection. The AC sleep-timeout write
        ; is a fallback for policies or drivers that do not honor a system request.
        SetSleepValues(plan, 0, normal.DC)
        SetDisplayValues(plan, KeepDisplayOn ? 0 : normal.DisplayAC,
            normal.DisplayDC)
        ; Override the battery lid action too: when AC drops out with the lid
        ; closed, Windows applies the DC lid action at once, before the
        ; AC-removal grace period can decide whether the dropout was transient.
        if KeepAwakeWithLidClosed {
            if normal.LidAC < 0 || normal.LidDC < 0
                throw Error("This computer does not expose a lid-close setting.")
            SetLidValues(plan, 0, 0)
        }
    }
    ReapplyActiveScheme()
}

SetSleepValues(plan, acSeconds, dcSeconds) {
    SetPowerSettingValues(plan,
        "{238c9fa8-0aad-41ed-83f4-97be242c8f20}",
        "{29f6c1db-86da-48c5-9fdb-f2b67b1f44da}",
        acSeconds, dcSeconds)
}

SetDisplayValues(plan, acSeconds, dcSeconds) {
    SetPowerSettingValues(plan,
        "{7516b95f-f776-4464-8c53-06167f40cc99}",
        "{3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e}",
        acSeconds, dcSeconds)
}

SetLidValues(plan, acValue, dcValue) {
    SetPowerSettingValues(plan,
        "{4f971e89-eebd-4455-a8de-9e59040e7347}",
        "{5ca83367-6e45-459f-a27b-476b1d01c936}",
        acValue, dcValue)
}

SetPowerSettingValues(plan, groupGuidText, settingGuidText, acValue, dcValue) {
    schemeGuid := GuidBuffer(plan)
    groupGuid := GuidBuffer(groupGuidText)
    settingGuid := GuidBuffer(settingGuidText)
    WritePowerValue("PowerWriteACValueIndex", schemeGuid,
        groupGuid, settingGuid, acValue)
    WritePowerValue("PowerWriteDCValueIndex", schemeGuid,
        groupGuid, settingGuid, dcValue)
}

; Written values take effect when the active plan is applied again. Apply
; whichever plan is active now, never a remembered one, so SteepAwake does not
; switch away from a plan Armoury Crate selected.
ReapplyActiveScheme() {
    schemeGuid := GuidBuffer(GetActiveScheme())
    result := DllCall("PowrProf\PowerSetActiveScheme",
        "Ptr", 0, "Ptr", schemeGuid.Ptr, "UInt")
    if result
        throw Error("Windows could not activate the updated power policy ("
            result ").")
}

GetActiveScheme() {
    schemePointer := 0
    result := DllCall("PowrProf\PowerGetActiveScheme",
        "Ptr", 0, "Ptr*", &schemePointer, "UInt")
    if result
        throw Error("Windows could not report the active power policy ("
            result ").")

    try {
        return GuidText(schemePointer)
    } finally {
        DllCall("Kernel32\LocalFree", "Ptr", schemePointer, "Ptr")
    }
}

PowerSchemes() {
    schemes := []
    guidBytes := Buffer(16, 0)
    loop {
        size := guidBytes.Size
        result := DllCall("PowrProf\PowerEnumerate",
            "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 16,
            "UInt", A_Index - 1, "Ptr", guidBytes.Ptr, "UInt*", &size, "UInt")
        ; ERROR_NO_MORE_ITEMS ends the list.
        if result = 259
            return schemes
        if result
            throw Error("Windows could not list the power plans (" result ").")
        schemes.Push(GuidText(guidBytes.Ptr))
    }
}

GuidText(guidPointer) {
    textBuffer := Buffer(78, 0)
    if !DllCall("Ole32\StringFromGUID2", "Ptr", guidPointer,
        "Ptr", textBuffer.Ptr, "Int", 39, "Int")
        throw Error("Windows returned an invalid power-policy identifier.")
    return StrGet(textBuffer, "UTF-16")
}

GuidBuffer(guidText) {
    if SubStr(guidText, 1, 1) != "{"
        guidText := "{" guidText "}"
    guidBytes := Buffer(16, 0)
    result := DllCall("Ole32\CLSIDFromString",
        "WStr", guidText, "Ptr", guidBytes.Ptr, "UInt")
    if result
        throw Error("Invalid power-policy identifier: " guidText)
    return guidBytes
}

ReadPowerValue(functionName, schemeGuid, groupGuid, settingGuid) {
    value := 0
    result := DllCall("PowrProf\" functionName,
        "Ptr", 0,
        "Ptr", schemeGuid.Ptr,
        "Ptr", groupGuid.Ptr,
        "Ptr", settingGuid.Ptr,
        "UInt*", &value,
        "UInt")
    if result
        throw Error(functionName " failed (" result ").")
    return value
}

WritePowerValue(functionName, schemeGuid, groupGuid, settingGuid, value) {
    result := DllCall("PowrProf\" functionName,
        "Ptr", 0,
        "Ptr", schemeGuid.Ptr,
        "Ptr", groupGuid.Ptr,
        "Ptr", settingGuid.Ptr,
        "UInt", value,
        "UInt")
    if result
        throw Error(functionName " failed (" result ").")
}

ExitTrayApp(*) {
    ShutdownTray()
}

HandleExit(exitReason, exitCode) {
    global SessionActive, TrayShuttingDown
    global TrayReadyEventHandle, TrayShutdownEventHandle
    global TrayStoppedEventHandle, TrayAwakeEventHandle, TrayMutexHandle

    if SessionActive && !TrayShuttingDown
        RestoreNormal(false)
    if !SessionActive
        try ReleaseNodePowerRequests()
    UnregisterPowerNotifications()
    if TrayStoppedEventHandle
        DllCall("Kernel32\SetEvent", "Ptr", TrayStoppedEventHandle)
    CloseTrayHandle(TrayReadyEventHandle)
    CloseTrayHandle(TrayShutdownEventHandle)
    CloseTrayHandle(TrayStoppedEventHandle)
    CloseTrayHandle(TrayAwakeEventHandle)
    CloseTrayHandle(TrayMutexHandle)
}
