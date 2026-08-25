# Установка и настройка Android Studio / эмулятора для отладки ceiling_calculator
# Запуск: powershell -ExecutionPolicy Bypass -File scripts\setup_android_studio.ps1

$ErrorActionPreference = "Stop"
$SdkRoot = "$env:LOCALAPPDATA\Android\Sdk"
$InstallerUrl = "https://edgedl.me.gvt1.com/android/studio/install/2025.3.4.7/android-studio-panda4-patch1-windows.exe"
$DownloadDir = Join-Path $env:USERPROFILE "Downloads"
$InstallerPath = Join-Path $DownloadDir "android-studio-panda4-patch1-windows.exe"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

Write-Step "Android Studio — помощник установки"
Write-Host "SDK будет здесь: $SdkRoot"

# 1. Скачать установщик, если ещё нет
if (-not (Test-Path $InstallerPath)) {
    Write-Step "Скачивание установщика (~1.4 ГБ) в Downloads..."
    Write-Host "URL: $InstallerUrl"
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Host "Готово: $InstallerPath"
} else {
    Write-Host "Установщик уже есть: $InstallerPath"
}

# 2. Запустить установщик
Write-Step "Запуск установщика Android Studio"
Write-Host @"
В мастере установки отметьте:
  - Android Studio
  - Android Virtual Device (эмулятор)
  - Android SDK
Дождитесь окончания и запустите Android Studio один раз (First Run Wizard).
"@

Start-Process -FilePath $InstallerPath -Wait:$false

# 3. PATH для текущей сессии (после установки SDK)
$platformTools = Join-Path $SdkRoot "platform-tools"
$emulator = Join-Path $SdkRoot "emulator"
if (Test-Path $platformTools) {
  $env:Path = "$platformTools;$emulator;" + $env:Path
  Write-Step "adb найден"
  & (Join-Path $platformTools "adb.exe") version
} else {
  Write-Host "adb пока не найден — сначала завершите установку Android Studio и SDK." -ForegroundColor Yellow
}

Write-Step "После первого запуска Android Studio"
Write-Host @"
1. More Actions -> SDK Manager:
   - Android SDK Platform 31 (или 34)
   - Android SDK Build-Tools
   - Android Emulator
2. Device Manager -> Create Device -> Pixel 6 -> API 31+ -> Finish
3. Запустите эмулятор (Play)

Установка APK:
  adb install -r bin\ceiling_calculator_alpha-2.1.4-arm64-v8a_armeabi-v7a-debug.apk

Логи при запуске приложения:
  adb logcat -c
  adb logcat | findstr /i "python kivy traceback AndroidRuntime ceiling"

Или из папки проекта (если есть APK):
  adb install -r путь\к\app-debug.apk
"@

Write-Host ""
Write-Host "Страница документации: https://developer.android.com/studio" -ForegroundColor Gray
