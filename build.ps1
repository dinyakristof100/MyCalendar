# build.ps1 -- a MEGBIZHATO debug build + telepites a telefonra.
#
# EZT futtasd, ne az Android Studio Run gombjat, ha parancssorbol buildelsz.
# Mindent sorosit, ezert nincs versenyhelyzet a plugin-lista regeneralasaban --
# ez okozta a visszatero "shared_preferences hianyzik" (build eldol) es a
# "toltokepernyon ragad" (MissingPluginException indulaskor) hibakat.
#
# Csak ASCII: a Windows PowerShell 5.1 a BOM nelkuli UTF-8-at rosszul olvassa,
# ekezet/emoji eltorne a scriptet -- ezert nincs benne egy sem.
#
# Hasznalat a projekt gyokerebol:   .\build.ps1

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# A projekt JDK-ja. A PATH-on levo java.exe Oracle JRE 8, azzal a gradlew el sem
# indul -- ezert itt kotelezo a teljes ut.
$env:JAVA_HOME = "E:\Applications\Android_Studio_2025.2.1\jbr"

# 1) Gradle demon leallitasa. Enelkul egy beragadt VFS-pillanatkepbol "nem letezo"
#    plugin-mappat szolgalhat ki (a "Plugin directory does not exist" build-hiba).
#    ponytail: minden buildnel leallitjuk (par mp hidegindulas). Ha ez zavaroan
#    lassu lenne, csak akkor kell, amikor tenyleg beragadt -- de a megbizhatosag er ennyit.
Write-Host "==> Gradle demon leallitasa..." -ForegroundColor Cyan
& "$root\android\gradlew.bat" --stop | Out-Null

# 2) Plugin-lista helyreallitasa (visszateszi a kiesett plugineket a registrantba).
Write-Host "==> flutter pub get..." -ForegroundColor Cyan
flutter pub get

# 3) Build. A Gradle-or (app/build.gradle.kts) a legelejen ellenorzi a registrantot,
#    es hangos, egyertelmu hibaval all le, ha barmi megis kiesett volna.
#
#    A versionCode-ot a telefonon levo verzio fole visszuk. A CI-release 1000+run_number-t
#    ad (release-apk.yml), a pubspec viszont csak +3 -- e nelkul minden helyi build
#    INSTALL_FAILED_VERSION_DOWNGRADE-del all le, amig release van fent a keszuleken.
#    Az adb-t nem tesszuk PATH-fuggove -- az Android SDK platform-tools-bol vesszuk.
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" }
$found = & $adb -s RFCW903FSHW shell dumpsys package com.mycalendar.my_calendar |
  Select-String 'versionCode=(\d+)' | Select-Object -First 1
# ponytail: a keszuleken talalt szam +1, nem sajat verziosema. Ha nincs telefon vagy
# nincs fent az app, marad a pubspec erteke. Ceiling: ha tobbszor buildelsz helyben,
# mint ahany CI-futas van, a debug szama elszalad a release elol -- olyankor a
# weboldalrol jovo release csak eltavolitas utan megy fel.
$buildArgs = if ($found) { @("--build-number", ([int]$found.Matches[0].Groups[1].Value + 1)) } else { @() }

Write-Host "==> flutter build apk --debug $buildArgs..." -ForegroundColor Cyan
flutter build apk --debug @buildArgs

# 4) Telepites a Galaxy S23-ra (adb id a project-status memoriabol).
Write-Host "==> Telepites a telefonra..." -ForegroundColor Cyan
& $adb -s RFCW903FSHW install -r "$root\build\app\outputs\flutter-apk\app-debug.apk"
if ($LASTEXITCODE -ne 0) { throw "Telepites SIKERTELEN (a telefon nincs csatlakoztatva vagy nincs USB-debug?). Az APK elkeszult, de NEM kerult fel a keszulekre." }

Write-Host ""
Write-Host "KESZ -- az app telepitve." -ForegroundColor Green
