# App ikon

`icon.svg` a **mesterpéldány** — minden ikon ebből származik. Ha az ikont
módosítod, ezt írd át, és kövesd a származtatottakban.

## PNG-k

| Fájl | Mire való |
|---|---|
| `icon_1024.png` | App Store / Play Store mester |
| `icon_512.png` | Play Store listing |
| `icon_192.png` | Android xxxhdpi |
| `icon_120.png` | iOS iPhone @2x |

Ezek **generált fájlok** — ne kézzel szerkeszd őket. Újragenerálás:

```bash
flutter test tool/generate_icons.dart
```

A generátor a Flutter saját `dart:ui`-jával rajzol és PNG-t ír, ezért nem kell
hozzá se ImageMagick, se Inkscape, se új csomag. Új méret: vedd fel a
`_sizes` listába. A méretet a script ellenőrzi is a PNG fejlécéből, tehát
csendben nem tud rossz méretű fájl keletkezni.

## Ami már él (Android)

Az Android nem SVG-ből, hanem saját vektorformátumból dolgozik, ezért a
mesterpéldány geometriája át van írva vector drawable-be:

| Fájl | Mi ez |
|---|---|
| `android/app/src/main/res/drawable/ic_launcher_foreground.xml` | az adaptive icon előtere (a naptár) |
| `android/app/src/main/res/values/ic_launcher_background.xml` | a háttérszín (`#3F51B5`, az app seed színe) |
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml` | a kettőt összefűző adaptive icon |
| `android/app/src/main/res/drawable/ic_notification.xml` | értesítés-ikon (egyszínű sziluett) |

Vektoros, ezért **nincs szükség PNG-kre**, és minden képernyősűrűségen éles.
API 26 alatt (minSdk 24) a régi `mipmap-*dpi/ic_launcher.png` fájlok a
tartalék — az érintett készülékek aránya elhanyagolható.

Ez a mappa **nincs** felvéve a `pubspec.yaml` assets közé, és nem is kell:
az ikonokat a rendszer tölti be az Android erőforrásokból, nem az app
futásidőben. Ha bekerülne, csak feleslegesen hizlalná az APK-t.

## Ami még hiányzik (iOS)

Az iOS nem tud vektoros app ikont, oda PNG-készlet kell (1024×1024
mesterből). Ez akkor lesz aktuális, amikor az iOS build egyáltalán szóba
kerül — az Macet igényel, és a `GoogleService-Info.plist` is hiányzik még.

Amikor odajutunk, a szokásos út:

```bash
# 1024-es PNG az SVG-ből (Macen a rsvg-convert vagy Inkscape megteszi)
rsvg-convert -w 1024 -h 1024 assets/icon/icon.svg -o assets/icon/icon_1024.png

# a többi méretet a flutter_launcher_icons generálja
flutter pub add --dev flutter_launcher_icons
```
