# Windows native toast notification branded as Warp
# Usage: powershell -ExecutionPolicy Bypass -File win-toast.ps1 -Title "title" -Body "body"
param(
    [string]$Title = "Claude Code",
    [string]$Body = "Task complete"
)

# --- Register Warp as a notification source (one-time, no admin needed) ---
$appId = "dev.warp.Warp"
$regPath = "HKCU:\SOFTWARE\Classes\AppUserModelId\$appId"
$iconPath = "$env:LOCALAPPDATA\Programs\Warp\icon.ico"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
New-ItemProperty -Path $regPath -Name "DisplayName" -Value "Warp" -PropertyType String -Force | Out-Null
if (Test-Path $iconPath) {
    New-ItemProperty -Path $regPath -Name "IconUri" -Value $iconPath -PropertyType ExpandString -Force | Out-Null
}

# --- Load Windows Runtime types ---
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null

# --- Build toast XML ---
$logoAttr = ""
if (Test-Path $iconPath) {
    $logoAttr = "<image placement=`"appLogoOverride`" src=`"$iconPath`" hint-crop=`"circle`"/>"
}

$toastXml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      $logoAttr
      <text>$Title</text>
      <text>$Body</text>
    </binding>
  </visual>
</toast>
"@

# --- Show notification ---
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($toastXml)
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
