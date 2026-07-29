;@Ahk2Exe-SetMainIcon ..\assets\indefinite-dark.ico
;@Ahk2Exe-AddResource ..\assets\normal-dark.ico, 201
;@Ahk2Exe-AddResource ..\assets\timed-dark.ico, 202
;@Ahk2Exe-AddResource ..\assets\indefinite-dark.ico, 203
;@Ahk2Exe-AddResource ..\assets\normal-light.ico, 204
;@Ahk2Exe-AddResource ..\assets\timed-light.ico, 205
;@Ahk2Exe-AddResource ..\assets\indefinite-light.ico, 206
;@Ahk2Exe-SetCompanyName smkwray
;@Ahk2Exe-SetDescription Keep Windows awake from the tray
;@Ahk2Exe-SetFileVersion 0.1.0
;@Ahk2Exe-SetInternalName SteepAwake
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Shane Wray
;@Ahk2Exe-SetName SteepAwake
;@Ahk2Exe-SetOrigFilename SteepAwake.exe
;@Ahk2Exe-SetProductName SteepAwake
;@Ahk2Exe-SetProductVersion 0.1.0

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
global SessionExpiry := ""
global SessionLabel := "Normal sleep"
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
    global SessionExpiry, SessionLabel

    try {
        if !SessionActive {
            values := ReadCurrentSleepValues()
            SessionPlan := values.Plan
            NormalAC := values.AC
            NormalDC := values.DC
        }

        SessionActive := true
        SessionExpiry := minutes ? DateAdd(A_Now, minutes, "Minutes") : ""
        SessionLabel := label
        SaveSession()
        SetSleepValues(SessionPlan, 0, 0)
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
    global SessionExpiry, SessionLabel

    if SessionActive && SessionPlan {
        try {
            SetSleepValues(SessionPlan, NormalAC, NormalDC)
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
    global SessionExpiry, SessionLabel

    SessionActive := Integer(IniRead(StateFile, "Session", "Active", "0")) = 1
    if !SessionActive {
        RefreshTray()
        return
    }

    SessionPlan := IniRead(StateFile, "Session", "Plan", "")
    NormalAC := Integer(IniRead(StateFile, "Session", "NormalAC", "0"))
    NormalDC := Integer(IniRead(StateFile, "Session", "NormalDC", "0"))
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
        SetSleepValues(SessionPlan, 0, 0)
        RefreshTray()
    } catch Error as err {
        MsgBox("Could not resume the saved " AppName " session.`n`n" err.Message,
            AppName, "Iconx")
        RestoreNormal(false)
    }
}

SaveSession() {
    global SessionActive, SessionPlan, NormalAC, NormalDC
    global SessionExpiry, SessionLabel

    IniWrite(SessionActive ? 1 : 0, StateFile, "Session", "Active")
    IniWrite(SessionPlan, StateFile, "Session", "Plan")
    IniWrite(NormalAC, StateFile, "Session", "NormalAC")
    IniWrite(NormalDC, StateFile, "Session", "NormalDC")
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

ReadCurrentSleepValues() {
    plan := GetActiveScheme()
    schemeGuid := GuidBuffer(plan)
    sleepGroupGuid := GuidBuffer("{238c9fa8-0aad-41ed-83f4-97be242c8f20}")
    sleepSettingGuid := GuidBuffer("{29f6c1db-86da-48c5-9fdb-f2b67b1f44da}")

    return {
        Plan: plan,
        AC: ReadPowerValue("PowerReadACValueIndex", schemeGuid,
            sleepGroupGuid, sleepSettingGuid),
        DC: ReadPowerValue("PowerReadDCValueIndex", schemeGuid,
            sleepGroupGuid, sleepSettingGuid)
    }
}

SetSleepValues(plan, acSeconds, dcSeconds) {
    schemeGuid := GuidBuffer(plan)
    sleepGroupGuid := GuidBuffer("{238c9fa8-0aad-41ed-83f4-97be242c8f20}")
    sleepSettingGuid := GuidBuffer("{29f6c1db-86da-48c5-9fdb-f2b67b1f44da}")

    WritePowerValue("PowerWriteACValueIndex", schemeGuid,
        sleepGroupGuid, sleepSettingGuid, acSeconds)
    WritePowerValue("PowerWriteDCValueIndex", schemeGuid,
        sleepGroupGuid, sleepSettingGuid, dcSeconds)

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
