$adb = "C:\Users\ravin\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$outTap = "D:\ravishori\AuHealth-AI\flutter_app\n09_tap.txt"
$uiXml = "D:\ravishori\AuHealth-AI\flutter_app\ui_dump.xml"

for ($i = 0; $i -lt 90; $i++) {
  Start-Sleep -Seconds 1
  $focus = & $adb -s emulator-5554 shell dumpsys window 2>$null | Select-String "mCurrentFocus"
  if ($focus -match "GrantPermissions") {
    & $adb -s emulator-5554 shell uiautomator dump /sdcard/ui.xml 2>$null | Out-Null
    & $adb -s emulator-5554 pull /sdcard/ui.xml $uiXml 2>$null | Out-Null
    $xml = Get-Content $uiXml -Raw -ErrorAction SilentlyContinue
    # Prefer resource-id for Don't allow (curly apostrophe in label).
    $m = [regex]::Match($xml, 'resource-id="com.android.permissioncontroller:id/permission_deny_and_dont_ask_again_button"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
    if (-not $m.Success) {
      $m = [regex]::Match($xml, 'resource-id="com.android.permissioncontroller:id/permission_deny_button"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
    }
    if ($m.Success) {
      $cx = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
      $cy = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
      & $adb -s emulator-5554 shell input tap $cx $cy
      "tapped deny button at $cx,$cy" | Set-Content $outTap
    } else {
      # Known Pixel dialog layout from prior dump
      & $adb -s emulator-5554 shell input tap 540 1453
      "fallback deny coords 540,1453" | Set-Content $outTap
    }
    break
  }
}
