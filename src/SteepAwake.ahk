;@Ahk2Exe-SetMainIcon ..\assets\indefinite-dark.ico
;@Ahk2Exe-AddResource ..\assets\normal-dark.ico, 201
;@Ahk2Exe-AddResource ..\assets\timed-dark.ico, 202
;@Ahk2Exe-AddResource ..\assets\indefinite-dark.ico, 203
;@Ahk2Exe-AddResource ..\assets\normal-light.ico, 204
;@Ahk2Exe-AddResource ..\assets\timed-light.ico, 205
;@Ahk2Exe-AddResource ..\assets\indefinite-light.ico, 206
;@Ahk2Exe-SetCompanyName smkwray
;@Ahk2Exe-SetDescription Keep Windows awake from the tray
;@Ahk2Exe-SetFileVersion 0.2.0
;@Ahk2Exe-SetInternalName SteepAwake
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Shane Wray
;@Ahk2Exe-SetName SteepAwake
;@Ahk2Exe-SetOrigFilename SteepAwake.exe
;@Ahk2Exe-SetProductName SteepAwake
;@Ahk2Exe-SetProductVersion 0.2.0

#Requires AutoHotkey v2.0
#SingleInstance Force

Persistent

global AppName := "SteepAwake"
global StateDirectory := EnvGet("LOCALAPPDATA") "\SteepAwake"
global StateFile := StateDirectory "\state.ini"
global StartupKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global StartupValueName := "SteepAwake"
global SessionActive := false
global SessionPlan := ""
global NormalAC := 0
global NormalDC := 0
global NormalDisplayAC := -1
global NormalDisplayDC := -1
global NormalLidAC := -1
global NormalLidDC := -1
global SessionExpiry := ""
global SessionLabel := "Normal sleep"
global KeepDisplayOn := false
global KeepAwakeWithLidClosed := false
global LastIconKey := ""
global IconResources := Map(
    "normal-dark", 201,
    "timed-dark", 202,
    "indefinite-dark", 203,
    "normal-light", 204,
    "timed-light", 205,
    "indefinite-light", 206)

DirCreate(StateDirectory)

if HasArgument("exit")
    ExitApp()

LoadPreferences()
BuildTrayMenu()
LoadSession()
SetTimer(CheckExpiration, 5000)
OnMessage(0x001A, HandleSettingChange)
OnExit(HandleExit)

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
    A_TrayMenu.Add("Keep display on while awake", ToggleKeepDisplayOn)
    A_TrayMenu.Add("Keep awake with lid closed", ToggleKeepAwakeWithLidClosed)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Start with Windows", ToggleStartup)
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
    global SessionActive, SessionPlan, NormalAC, NormalDC
    global NormalDisplayAC, NormalDisplayDC, NormalLidAC, NormalLidDC
    global SessionExpiry, SessionLabel

    try {
        if !SessionActive {
            values := ReadCurrentPowerValues()
            SessionPlan := values.Plan
            NormalAC := values.AC
            NormalDC := values.DC
            NormalDisplayAC := values.DisplayAC
            NormalDisplayDC := values.DisplayDC
            NormalLidAC := values.LidAC
            NormalLidDC := values.LidDC
        }

        SessionActive := true
        SessionExpiry := minutes ? DateAdd(A_Now, minutes, "Minutes") : ""
        SessionLabel := label
        SaveSession()
        ApplySessionPolicy()
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
    global SessionActive, SessionPlan, NormalAC, NormalDC
    global NormalDisplayAC, NormalDisplayDC, NormalLidAC, NormalLidDC
    global SessionExpiry, SessionLabel

    if SessionActive && SessionPlan {
        try {
            SetSleepValues(SessionPlan, NormalAC, NormalDC)
            if NormalDisplayAC >= 0 && NormalDisplayDC >= 0
                SetDisplayValues(SessionPlan, NormalDisplayAC, NormalDisplayDC)
            if NormalLidAC >= 0 && NormalLidDC >= 0
                SetLidValues(SessionPlan, NormalLidAC, NormalLidDC)
        } catch Error as err {
            MsgBox("Could not restore the normal sleep policy.`n`n" err.Message,
                AppName, "Iconx")
            return false
        }
    }

    SessionActive := false
    SessionPlan := ""
    NormalAC := 0
    NormalDC := 0
    NormalDisplayAC := -1
    NormalDisplayDC := -1
    NormalLidAC := -1
    NormalLidDC := -1
    SessionExpiry := ""
    SessionLabel := "Normal sleep"
    SaveSession()
    RefreshTray()

    if showNotice
        TrayTip("The normal Windows sleep policy is active.", AppName, 1)
    return true
}

CheckExpiration() {
    global SessionActive, SessionExpiry

    if SessionActive && SessionExpiry {
        if DateDiff(SessionExpiry, A_Now, "Seconds") <= 0 {
            RestoreNormal(true)
        } else {
            RefreshTray()
        }
    }
}

LoadSession() {
    global SessionActive, SessionPlan, NormalAC, NormalDC
    global NormalDisplayAC, NormalDisplayDC, NormalLidAC, NormalLidDC
    global SessionExpiry, SessionLabel

    SessionActive := Integer(IniRead(StateFile, "Session", "Active", "0")) = 1
    if !SessionActive {
        RefreshTray()
        return
    }

    SessionPlan := IniRead(StateFile, "Session", "Plan", "")
    NormalAC := Integer(IniRead(StateFile, "Session", "NormalAC", "0"))
    NormalDC := Integer(IniRead(StateFile, "Session", "NormalDC", "0"))
    NormalDisplayAC := Integer(IniRead(
        StateFile, "Session", "NormalDisplayAC", "-1"))
    NormalDisplayDC := Integer(IniRead(
        StateFile, "Session", "NormalDisplayDC", "-1"))
    NormalLidAC := Integer(IniRead(StateFile, "Session", "NormalLidAC", "-1"))
    NormalLidDC := Integer(IniRead(StateFile, "Session", "NormalLidDC", "-1"))
    SessionExpiry := IniRead(StateFile, "Session", "Expiry", "")
    SessionLabel := IniRead(StateFile, "Session", "Label", "Indefinitely")

    if !SessionPlan {
        RestoreNormal(false)
        return
    }

    if SessionExpiry && DateDiff(SessionExpiry, A_Now, "Seconds") <= 0 {
        RestoreNormal(false)
        return
    }

    try {
        if NormalDisplayAC < 0 || NormalDisplayDC < 0 {
            values := ReadCurrentPowerValues()
            NormalDisplayAC := values.DisplayAC
            NormalDisplayDC := values.DisplayDC
            NormalLidAC := values.LidAC
            NormalLidDC := values.LidDC
            SaveSession()
        }
        ApplySessionPolicy()
        RefreshTray()
    } catch Error as err {
        MsgBox("Could not resume the saved " AppName " session.`n`n" err.Message,
            AppName, "Iconx")
        RestoreNormal(false)
    }
}

SaveSession() {
    global SessionActive, SessionPlan, NormalAC, NormalDC
    global NormalDisplayAC, NormalDisplayDC, NormalLidAC, NormalLidDC
    global SessionExpiry, SessionLabel

    IniWrite(SessionActive ? 1 : 0, StateFile, "Session", "Active")
    IniWrite(SessionPlan, StateFile, "Session", "Plan")
    IniWrite(NormalAC, StateFile, "Session", "NormalAC")
    IniWrite(NormalDC, StateFile, "Session", "NormalDC")
    IniWrite(NormalDisplayAC, StateFile, "Session", "NormalDisplayAC")
    IniWrite(NormalDisplayDC, StateFile, "Session", "NormalDisplayDC")
    IniWrite(NormalLidAC, StateFile, "Session", "NormalLidAC")
    IniWrite(NormalLidDC, StateFile, "Session", "NormalLidDC")
    IniWrite(SessionExpiry, StateFile, "Session", "Expiry")
    IniWrite(SessionLabel, StateFile, "Session", "Label")
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

    KeepDisplayOn := Integer(IniRead(
        StateFile, "Preferences", "KeepDisplayOn", "0")) = 1
    KeepAwakeWithLidClosed := Integer(IniRead(
        StateFile, "Preferences", "KeepAwakeWithLidClosed", "0")) = 1
}

SavePreferences() {
    IniWrite(KeepDisplayOn ? 1 : 0,
        StateFile, "Preferences", "KeepDisplayOn")
    IniWrite(KeepAwakeWithLidClosed ? 1 : 0,
        StateFile, "Preferences", "KeepAwakeWithLidClosed")
}

ToggleKeepDisplayOn(*) {
    global KeepDisplayOn

    try {
        enabled := !KeepDisplayOn
        if SessionActive {
            if enabled
                SetDisplayValues(SessionPlan, 0, 0)
            else
                SetDisplayValues(SessionPlan, NormalDisplayAC, NormalDisplayDC)
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
    global KeepAwakeWithLidClosed

    try {
        enabled := !KeepAwakeWithLidClosed
        if enabled && !SessionActive {
            values := ReadCurrentPowerValues()
            if values.LidAC < 0 || values.LidDC < 0
                throw Error("This computer does not expose a lid-close setting.")
        }
        if SessionActive {
            if NormalLidAC < 0 || NormalLidDC < 0
                throw Error("This computer does not expose a lid-close setting.")
            if enabled
                SetLidValues(SessionPlan, 0, 0)
            else
                SetLidValues(SessionPlan, NormalLidAC, NormalLidDC)
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
    if KeepDisplayOn {
        try A_TrayMenu.Check("Keep display on while awake")
    } else {
        try A_TrayMenu.Uncheck("Keep display on while awake")
    }

    if KeepAwakeWithLidClosed {
        try A_TrayMenu.Check("Keep awake with lid closed")
    } else {
        try A_TrayMenu.Uncheck("Keep awake with lid closed")
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

RefreshStartupCheck() {
    if IsStartupEnabled() {
        try A_TrayMenu.Check("Start with Windows")
    } else {
        try A_TrayMenu.Uncheck("Start with Windows")
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
    if A_IsCompiled
        return '"' A_ScriptFullPath '"'
    return '"' A_AhkPath '" "' A_ScriptFullPath '"'
}

HasArgument(expected) {
    for argument in A_Args
        if StrLower(argument) = StrLower(expected)
            return true
    return false
}

ReadCurrentPowerValues() {
    plan := GetActiveScheme()
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
        Plan: plan,
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
    SetSleepValues(SessionPlan, 0, 0)
    if KeepDisplayOn
        SetDisplayValues(SessionPlan, 0, 0)
    if KeepAwakeWithLidClosed {
        if NormalLidAC < 0 || NormalLidDC < 0
            throw Error("This computer does not expose a lid-close setting.")
        SetLidValues(SessionPlan, 0, 0)
    }
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
        textBuffer := Buffer(78, 0)
        if !DllCall("Ole32\StringFromGUID2", "Ptr", schemePointer,
            "Ptr", textBuffer.Ptr, "Int", 39, "Int")
            throw Error("Windows returned an invalid power-policy identifier.")
        return StrGet(textBuffer, "UTF-16")
    } finally {
        DllCall("Kernel32\LocalFree", "Ptr", schemePointer, "Ptr")
    }
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
    if RestoreNormal(false)
        ExitApp()
}

HandleExit(exitReason, exitCode) {
    global SessionActive
    if SessionActive
        RestoreNormal(false)
}
