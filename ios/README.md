# BillBox for iPhone

The iPhone version of BillBox, with the same functions as BillBox for macOS v14.11. It is native Swift and SwiftUI, needs iOS 16 or later and runs on iPhone XR and newer.

Everything runs on the phone. There is no server and no Node. The app keeps the same SQLite files as the Mac (one per company plus `registry.db`), so backups move between Mac and iPhone in both directions.

- `FEATURE_PARITY.md` is the feature contract. Every item is ticked, and the end of the file says how each part was verified.
- `ARCHITECTURE.md` describes how the app is put together.

## Build automatically (one command)

In Terminal on the Mac, run these from the `ios` folder:

```
cd path/to/fmcg-distributor/ios
chmod +x build.sh
./build.sh            # runs the unit tests, then builds and installs on the iPhone plugged in by USB
./build.sh sim        # build and open in the iPhone simulator
./build.sh test       # unit tests only
./build.sh device     # install on the iPhone without running the tests
./build.sh run        # install, start on the iPhone and show its log here (a crash shows its reason)
./build.sh crashlog   # copy BillBox crash reports from the iPhone and show the newest
./build.sh ipa        # make build/ipa/BillBox.ipa (for Sideloadly / AltStore)
```

- **Signing team**: the script finds your team by itself once you have signed in to Xcode › Settings › Accounts with your Apple ID.
- **Free Apple ID**: you may need your own app identifier, for example `BUNDLE_ID=com.yourname.billbox ./build.sh`.
- **Xcode 14.2 on Monterey** can install only on iPhones running iOS 16 or older:
  - Installing from Terminal also needs `brew install ios-deploy`.
  - For an iPhone on iOS 17 or newer, run `./build.sh ipa` and install `BillBox.ipa` with Sideloadly or AltStore. The script tells you when this applies.
- Logs of every step go to `ios/build/*.log`.
- If BillBox ever closes by itself, it shows the reason the next time it opens ("Last close", with Share). `./build.sh crashlog` reads the phone's own crash reports (Xcode 15+, or `brew install libimobiledevice` with Xcode 14).

## Build in Xcode

You need a Mac with **Xcode 14.2 or newer**. The code is Swift 5.7 and iOS 16 compatible, so Xcode 14.2 on macOS Monterey is enough.

1. Open `ios/BillBox.xcodeproj`.
2. Select the **BillBox** target, then **Signing & Capabilities**:
   - Choose your **Team**. A free Apple ID works for your own phone.
   - If Xcode reports that the bundle identifier `com.local.billbox` is taken, change it to something unique, such as `com.yourname.billbox`.
   - If you change the bundle identifier, the background-backup identifier in `BillBox/Info.plist` can stay `com.local.billbox.backup`. It does not have to match.
3. Choose your iPhone, or a simulator such as iPhone XR or iPhone 15 Pro Max, and press **Run** (⌘R).
   - On a real phone the first time: Settings › General › VPN & Device Management › trust your developer certificate.
4. Run the unit tests with **Product › Test** (⌘U). This needs a simulator.
   - The tests replay answers recorded from the Mac engine on the iPhone engine: a full working session, 1,600+ random bills, the supplier-bill parser, your three supplier PDFs, BillMath on 3,000 bills, and restoring a Mac backup (Replace, Merge, one company file).
   - They also check that an iPhone backup has the Mac's layout and restores.

A free Apple ID signs the app for 7 days. After that, run it from Xcode again. Your data stays on the phone.

## Moving your books between Mac and iPhone

- **Mac → iPhone**:
  1. On the Mac, press Settings › Backup › **Back up now**.
  2. Copy the new `FMCG_Backup_…` folder to the iPhone: AirDrop it into Files, or put it in iCloud Drive.
  3. In BillBox on the iPhone, open More › Settings › Backup › **Restore from a backup folder…**, pick the folder, then choose **Replace** or **Merge**.
- **iPhone → Mac**:
  1. On the iPhone, press **Back up now**. Backups go to Files › On My iPhone › BillBox › DistributorProBackups, or to the folder you chose with **Choose…**.
  2. Copy the folder to the Mac.
  3. On the Mac, open Settings › Backup › Restore from a backup folder….
- A single company file (`.db`) restores the same way with **Restore one company file (.db)…**.

## What works differently on iPhone (as approved)

- **Daily backup**: while BillBox is open, it runs at the set time, exactly as on the Mac. It also catches up when you open BillBox or come back to it. When BillBox is closed, iOS decides when, or whether, it gives the app background time, so a backup can be hours late. Opening the app makes up for it.
- **"Also back up whenever I quit the app"**: iOS has no quit, so this backup runs each time you leave BillBox (go to the Home Screen or switch apps).
- **WhatsApp sending** works only while BillBox is open on screen. If you leave during a send, it finishes when you come back.
- **Printer**: choose an AirPrint printer once in More › Settings › Printing. It is remembered on this iPhone only. The Mac's printer setting in the books is left untouched.
- **Supplier PDFs** are read by the Mac's own reader (pdf.js 1.10.100, as in pdf-parse, plus the Mac's line-joining code) running inside the app, so each page reads exactly as on the Mac. **Scanned PDFs** (no text layer) are read with Apple's on-device text recognition instead of tesseract.
- **Files**: Save PDF / Export to Excel open the share sheet. **Save to Files** there picks the folder.
- **Keyboard**: with a hardware keyboard, the Mac shortcuts work: ⌘1–⌘9, ⌘K, ⌘N, ⌘S, ↑/↓, Esc. Each one also has a button.

## Importing your Marg ERP books

In Marg: Reports › Management Report › Data Transfer Utility › Export All Data › CSV. On the Mac: Settings › Import from Marg; on the iPhone: Settings › Import from Marg ERP. Pick the .zip (or the folder it unzips to), read the checks, then Import. Open the company you want the data in first (a new company is best for a first import).

## For developers

- `BillBoxCore/`: the engine, a line-for-line Swift port of the Mac app's server (`backend/src`). The app target compiles these sources directly. It is also a Swift package:
  - `swift build` builds it on macOS or Linux.
  - `swift test` runs the golden tests.
- `BillBox/`: the iPhone screens, ported from `macos/Sources/DistributorPro`.
- `tests/parity/`: replays the same steps on the Mac's Node engine and on the iOS engine, then compares them. Needs Node 22+ and the Swift toolchain.
  - `run.sh`: the working session and the GST Excel file
  - `run_more.sh`: the parser, random bills and PDF page text
  - `test_backup.py WORK BBCHECK`: backups in both directions
  - `make_golden.py`: re-records the Mac answers used by the unit tests. Run it after any change to `backend/src`.
- `tests/typecheck/stubs/build.sh`: type-checks all app code on Linux against an iOS 16 SDK surface (no Xcode needed).
- `../macos/tests/typecheck/build.sh`: the same for the Mac app (AppKit surface stubbed), so Mac edits are checked without a Mac.
- `tools/make_pdfreader.py`: rebuilds `BillBox/Resources/PDFReader/reader.js` from the Mac's `backend/src/services/pdfExtract.js`. `tests/pdfreader/browser_check.py a.pdf …` checks the iPhone reader against the Mac's on real PDFs.
- `tools/make_xcodeproj.py`: regenerates `BillBox.xcodeproj` after adding or removing files. `tools/check_pbxproj.py` validates it.
