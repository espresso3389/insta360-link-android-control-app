param(
    [string]$Device = "",
    [Parameter(Mandatory = $true)]
    [ValidateSet("init", "list", "connect", "start", "stop", "setpid", "detach", "policy", "manual", "zoom", "activate", "activate2", "probeptz", "dumpxu", "probexu", "replaylinux")]
    [string]$Cmd,
    [int]$VendorId = 0,
    [int]$ProductId = 0,
    [string]$Mode = "largest",
    [float]$KpX = -1.2,
    [float]$KiX = 0.0,
    [float]$KdX = -0.12,
    [float]$KpY = 1.0,
    [float]$KiY = 0.0,
    [float]$KdY = 0.10,
    [float]$Pan = 0.0,
    [float]$Tilt = 0.0,
    [float]$Zoom = 0.0,
    [int]$DurationMs = 300
)

$pkg = "com.example.insta360link_android_test"
$activity = "$pkg/.MainActivity"
$adb = "adb"
if ($Device -ne "") {
    $adb = "adb -s $Device"
}

function Run-Adb([string]$Command) {
    Write-Host ">> $Command"
    Invoke-Expression $Command
}

$base = "$adb shell am start -n $activity --es cmd $Cmd"
switch ($Cmd) {
    "connect" {
        if ($VendorId -eq 0 -or $ProductId -eq 0) {
            throw "connect requires -VendorId and -ProductId"
        }
        $base += " --ei vid $VendorId --ei pid $ProductId"
    }
    "policy" {
        $base += " --es mode $Mode"
    }
    "setpid" {
        $base += " --ef kpX $KpX --ef kiX $KiX --ef kdX $KdX --ef kpY $KpY --ef kiY $KiY --ef kdY $KdY"
    }
    "manual" {
        $base += " --ef pan $Pan --ef tilt $Tilt --ei durationMs $DurationMs"
    }
    "zoom" {
        $base += " --ef zoom $Zoom --ei durationMs $DurationMs"
    }
}

Run-Adb "$adb logcat -c"
Run-Adb $base
Start-Sleep -Milliseconds 700
Run-Adb "$adb logcat -d -s Insta360LinkTracker"
