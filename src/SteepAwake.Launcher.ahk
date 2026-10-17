; SteepAwake public launcher. It is intentionally unelevated and has no tray UI.
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon

if HasArgument("--syntax-check")
    ExitApp(0)

ExitApp(RunLauncherMode())

RunLauncherMode() {
    try {
        if HasArgument("--shutdown")
            return SignalTrayShutdown(HasArgument("--wait"))
        return StartElevatedTray()
    } catch Error as err {
        details := err.Message
        try details .= "`n`nWhat: " err.What "`nLine: " err.Line
        LogLauncherFailure(details)
        MsgBox("Could not start SteepAwake.`n`n" details,
            "SteepAwake", "Iconx")
        return 1
    }
}

StartElevatedTray() {
    sid := CurrentUserSid()
    readyName := "Local\SteepAwake.Tray.Ready." sid
    ready := CreateNamedEvent(readyName)
    try {
        if WaitForEvent(ready, 0) = 0
            return 0

        ResetEvent(ready)
        scheduler := ComObject("Schedule.Service")
        scheduler.Connect()
        task := scheduler.GetFolder("\SteepAwake").GetTask("Tray")
        task.Run(0)

        if WaitForEvent(ready, 15000) = 0
            return 0
        throw Error("The elevated tray did not signal readiness within 15 seconds.")
    } finally {
        CloseHandle(ready)
    }
}

SignalTrayShutdown(waitForStopped) {
    sid := CurrentUserSid()
    shutdownName := "Local\SteepAwake.Tray.Shutdown." sid
    stoppedName := "Local\SteepAwake.Tray.Stopped." sid
    shutdown := OpenNamedEvent(shutdownName, 0x00100002)
    if !shutdown
        return 0

    try {
        if !DllCall("Kernel32\SetEvent", "Ptr", shutdown)
            throw Error("Windows could not signal the elevated tray ("
                A_LastError ").")
        if !waitForStopped
            return 0

        stopped := OpenNamedEvent(stoppedName, 0x00100000)
        if !stopped
            throw Error("The elevated tray did not expose its stopped event.")
        try {
            if WaitForEvent(stopped, 30000) != 0
                throw Error("The elevated tray did not finish restoration within 30 seconds.")
        } finally {
            CloseHandle(stopped)
        }
        return 0
    } finally {
        CloseHandle(shutdown)
    }
}

CreateNamedEvent(name) {
    handle := DllCall("Kernel32\CreateEventW",
        "Ptr", 0, "Int", 1, "Int", 0, "WStr", name, "Ptr")
    if !handle
        throw Error("Windows could not create the SteepAwake control event ("
            A_LastError ").")
    return handle
}

OpenNamedEvent(name, access) {
    return DllCall("Kernel32\OpenEventW",
        "UInt", access, "Int", 0, "WStr", name, "Ptr")
}

WaitForEvent(handle, timeoutMs) {
    return DllCall("Kernel32\WaitForSingleObject",
        "Ptr", handle, "UInt", timeoutMs, "UInt")
}

ResetEvent(handle) {
    if !DllCall("Kernel32\ResetEvent", "Ptr", handle)
        throw Error("Windows could not reset the SteepAwake ready event ("
            A_LastError ").")
}

CloseHandle(handle) {
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
        CloseHandle(token)
    }
}

LogLauncherFailure(message) {
    try {
        directory := EnvGet("LOCALAPPDATA") "\SteepAwake"
        DirCreate(directory)
        FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " " message "`n",
            directory "\launch.log", "UTF-8")
    }
}

HasArgument(expected) {
    for argument in A_Args
        if StrLower(argument) = StrLower(expected)
            return true
    return false
}
