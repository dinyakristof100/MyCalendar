# release.ps1 -- uj APK kiadasa: build-szam +1, release build, feltoltes GitHub Release-be.
#
# A weboldal (docs/index.html) letoltes gombja MINDIG a legfrissebb release-t huzza:
#   https://github.com/dinyakristof100/MyCalendar/releases/latest/download/mycalendar.apk
# Ez a link csak akkor tolti az UJ APK-t, ha a versionCode (a pubspec +N) nott -- kulonben
# az Android nem engedi felul-telepiteni a mar fent levot. Ezert emel ez a szkript minden
# kiadasnal automatikusan.
#
# Csak ASCII (a PS 5.1 a BOM nelkuli UTF-8-at rosszul olvassa) -- lasd build.ps1.
#
# Hasznalat a projekt gyokerebol:
#   .\release.ps1            # emel + buildel + kiad
#   .\release.ps1 -DryRun    # csak megmutatja, milyen verzio lenne (nem ir, nem buildel)

param([switch]$DryRun)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$env:JAVA_HOME = "E:\Applications\Android_Studio_2025.2.1\jbr"

$pubspec = Join-Path $root "pubspec.yaml"
$asset   = "mycalendar.apk"
$apkPath = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"

# 1) Build-szam +1 a pubspec-ben:  version: X.Y.Z+N  ->  X.Y.Z+(N+1)
$pattern = '(?m)^(version:\s*)([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)'
$content = Get-Content $pubspec -Raw
if ($content -notmatch $pattern) {
    throw "Nem talalom a 'version: X.Y.Z+N' sort a pubspec.yaml-ben."
}
$name = $Matches[2]
$code = [int]$Matches[3] + 1
$newVersion = "$name+$code"
$tag = "v$newVersion"

if ($DryRun) {
    Write-Host "DryRun: a kovetkezo verzio $newVersion (versionCode=$code), tag=$tag" -ForegroundColor Yellow
    return
}

$content = [regex]::Replace($content, $pattern, "`${1}$newVersion")
# UTF-8 BOM NELKUL -- BOM-mal a pub/YAML parser elszallhat (lasd build.ps1 fejlec).
[IO.File]::WriteAllText($pubspec, $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "==> Uj verzio: $newVersion (versionCode=$code)" -ForegroundColor Cyan

# 2) Megbizhato build (ugyanaz a plugin-or vedelem, mint build.ps1: elobb demon-stop + pub get).
& "$root\android\gradlew.bat" --stop | Out-Null
flutter pub get
# ponytail: universalis (fat) release APK, egyetlen fajl -> stabil 'mycalendar.apk' link.
# Ha a meret zavaro (~tobb tiz MB), --split-per-abi kisebb, de az tobb assetet ad es elrontja
# az egy-linkes letoltest -> maradjon universalis, amig nem faj.
flutter build apk --release

# 3) Allando nevu asset a stabil linkhez, majd kiadas GitHub Release-be.
$assetPath = Join-Path $root $asset
Copy-Item $apkPath $assetPath -Force

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    Write-Host "==> GitHub Release: $tag ..." -ForegroundColor Cyan
    gh release create $tag $assetPath --title $tag --notes "MyCalendar $newVersion"
    Remove-Item $assetPath -Force
    Write-Host ""
    Write-Host "KESZ -- fent van. A weboldal gombja mar EZT tolti." -ForegroundColor Green
    Write-Host "Ne felejtsd: a pubspec verzio-emelest commitold + pushold." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "A 'gh' (GitHub CLI) nincs telepitve. Ket lehetoseg:" -ForegroundColor Yellow
    Write-Host "  1) Egyszeri telepites, utana automatikus:"
    Write-Host "        winget install --id GitHub.cli"
    Write-Host "        gh auth login"
    Write-Host "     majd futtasd ujra:  .\release.ps1  (de a verzio mar emelve van, lasd lent)"
    Write-Host "  2) Kezi feltoltes: Releases -> 'Draft a new release',"
    Write-Host "        tag = $tag , es huzd fel EZT a fajlt PONTOSAN ezen a neven ($asset):"
    Write-Host "           $assetPath"
    Write-Host ""
    Write-Host "FONTOS: az asset neve maradjon '$asset', kulonben a weboldal linkje eltorik." -ForegroundColor Yellow
    Write-Host "A pubspec verzio mar emelve ($newVersion) -- ezt is commitold + pushold." -ForegroundColor Yellow
}
