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
#    A versionCode a build IDEJE: eltelt percek 2020-01-01 ota -- ugyanaz a keplet,
#    mint a CI-release-e (release-apk.yml). Igy a helyi es a CI-build egyetlen monoton
#    sorban all: mindig a frissebb megy fel a telefonra, barmelyik oldalrol jon, es
#    nincs INSTALL_FAILED_VERSION_DOWNGRADE egyik iranyban sem.
#    Az adb-t nem tesszuk PATH-fuggove -- az Android SDK platform-tools-bol vesszuk.
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" }
$epoch = [datetime]::new(2020, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
$buildArgs = @("--build-number", [int]([datetime]::UtcNow - $epoch).TotalMinutes)

Write-Host "==> flutter build apk --debug $buildArgs..." -ForegroundColor Cyan
flutter build apk --debug @buildArgs

# 4) Telepites a Galaxy S23-ra (adb id a project-status memoriabol).
Write-Host "==> Telepites a telefonra..." -ForegroundColor Cyan
& $adb -s RFCW903FSHW install -r "$root\build\app\outputs\flutter-apk\app-debug.apk"
if ($LASTEXITCODE -ne 0) { throw "Telepites SIKERTELEN (a telefon nincs csatlakoztatva vagy nincs USB-debug?). Az APK elkeszult, de NEM kerult fel a keszulekre." }

Write-Host ""
Write-Host "KESZ -- az app telepitve." -ForegroundColor Green
