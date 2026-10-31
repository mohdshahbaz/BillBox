# BillBox for Android

Android 12 (API 31) and newer, phones and tablets. Every feature of the iPhone and Mac apps, with Android's own design.

## Build and run on your phone

1. On the phone, once: **Settings › About phone ›** tap **Build number** seven times; then **Settings › System ›
   Developer options › USB debugging › On**.
2. Plug the phone into the computer and tap **Allow** on *Allow USB debugging?*.
3. In a Terminal:

```bash
cd android
./build.sh          # builds, installs and opens BillBox on the phone
```

The script needs Java 17+ and the Android SDK. With **Android Studio** installed (and opened once) both are found
automatically. Without it, `./build.sh setup` downloads only what BillBox needs (into `android/.sdk`). The first build
downloads Gradle and the libraries (a few hundred MB, once).

| Command | What it does |
|---|---|
| `./build.sh` | build, install on the connected phone, open BillBox |
| `./build.sh run` | the same, then shows BillBox's log (a crash shows its reason) |
| `./build.sh apk` | `android/build/BillBox-debug.apk` to copy to any phone |
| `./build.sh release` | release APK (signed with `keystore.properties` when present) |
| `./build.sh install` | install the last APK and open it |
| `./build.sh wifi 192.168.1.20:37000` | connect over Wi-Fi debugging (Developer options › Wireless debugging); `pair` first if asked |
| `./build.sh devices` / `logcat` | list phones / show the log |
| `./build.sh test` | engine parity against the Mac engine (Node.js 22, Python 3) |
| `./build.sh engine` | rebuild the bundled engine after changing `backend/src` (Node.js 22) |
| `./build.sh typecheck` | check the Kotlin without the Android SDK |

With more than one phone connected: `SERIAL=<id from devices> ./build.sh`. A second copy beside the first:
`APP_ID=com.local.billbox2 ./build.sh`.

## How it is built

- **Engine** — the Mac's `backend/src`, unchanged, bundled by `engine/build.mjs` into
  `app/src/main/assets/engine/engine.js` and run in a hidden WebView. Small bridges (`app/.../engine/`) give it Android's
  SQLite (`SqlBridge`), files (`FsBridge`), internet (`NetBridge`) and on-phone text recognition for scanned PDFs and
  photos (`OcrBridge`, ML Kit). Books are kept in the app's storage in the Mac's format (`files/data`), backups in
  `files/DistributorProBackups` (or a folder visible over USB, Settings › Backup).
- **App** — Kotlin, Jetpack Compose, Material 3 (`app/src/main/java/com/local/billbox`): `screens/` (Billing, All Bills,
  Stock, Parties, Purchases, Debit Notes, Salesmen, Books & GST, Dashboard, Settings), `ui/` (theme, navigation, the
  adjustable table, forms), `print/` (the bill layouts as PDF and Android's print service), `system/` (files, camera,
  share, WhatsApp, daily backup with WorkManager, crash report).
- **Checks** — `engine/test/run.sh` (engine parity), `tests/typecheck/check.sh` (Kotlin type-check against stubs of
  the Android SDK and Compose).

## Android-specific behaviour

- **Printing**: BillBox draws the bill (half sheets / two on A4 / full A4, copy labels, columns, amount in words,
  signature) as a PDF; Print opens Android's print screen (any printer with a print service, or Save as PDF). Settings ›
  Printing can skip BillBox's preview. Bills are marked printed when sent to the printer.
- **WhatsApp**: WhatsApp opens on the customer's chat with the bill PDF attached and the message filled in; you tap Send.
- **Backup**: daily while the app is open (as on the Mac) and, when it is closed, within about an hour of the backup time.
  Leaving the app counts as quitting for "back up when I quit". Save a copy of any backup to Drive, a USB drive or
  Downloads from Settings › Backup.
- **Files**: restore from a backup folder, a .zip or one company .db; Marg import from the CSV folder or its .zip; e-way
  bill files and Excel are saved where you choose.
