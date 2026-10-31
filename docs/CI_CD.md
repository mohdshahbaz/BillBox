# Building and releasing on GitHub

The repository builds itself on GitHub (GitHub Actions). Two workflows live in `.github/workflows/`:

| Workflow | Runs when | What it does |
|---|---|---|
| **CI** (`ci.yml`) | every push to `main` and every pull request | Mac engine checks; the iPhone engine and the Android engine replayed against the Mac engine (461-step working session, 1,647 random bills, PDF parser, Marg import, backups across apps, unit tests); builds the Android app and keeps the debug APK for 14 days (Actions › the run › Artifacts). |
| **Release** (`release.yml`) | you push a tag `v…` (or run it by hand) | Builds the Android APK, the Mac app (one app for Apple silicon and Intel) and the iPhone `.ipa`, and publishes them together as a GitHub release with install notes and the list of changes. |

## Upload the project (first time and after every change)

```bash
./github.sh
```

The first time it connects the folder to `github.com/mohdshahbaz/BillBox` (GitHub asks you to sign in: use your
GitHub user name and a personal access token as the password, or install GitHub Desktop / `gh auth login` once).
Your real business data stays on the Mac: the private test folders (your Marg backup and supplier bills), the Android
release key and `keystore.properties` are kept out, and the script stops if any of them would be uploaded. On GitHub
the tests that need them are skipped; on your Mac they still run.

If real data was ever uploaded before, run `./github.sh fresh` once instead: it replaces GitHub's history with one
clean upload (your old local history is kept in a `.git-old-*` folder). A normal `./github.sh` refuses to upload while
the saved history still holds real data.

## Make a release

```bash
./github.sh release 15.2.0
```

or by hand:

```bash
git tag v15.2.0
git push origin v15.2.0
```

or on GitHub: **Actions › Release › Run workflow**, type the version (e.g. `15.2.1`), Run. A version with a dash
(`15.3.0-beta1`), or the "pre-release" tick, makes a test release that is not shown as the latest.

About 20–30 minutes later the release is under **Releases** with:

- `BillBox-android-<version>.apk` — versionName from the tag, versionCode = major·10000 + minor·100 + patch
  (15.2.0 → 150200), so each release updates the one before.
- `BillBox-mac-<version>.zip` — `BillBox.app` for Apple silicon and Intel Macs (ad-hoc signed; first open with
  right-click › Open, or `xattr -dr com.apple.quarantine /Applications/BillBox.app`).
- `BillBox-iphone-<version>-unsigned.ipa` — install with Sideloadly or AltStore, which sign it with your Apple ID.

## One-time: the Android release key (do this before the first release)

Android only updates an app signed with the same key. Make the key once on your Mac and give it to GitHub as secrets:

```bash
cd android
tools/make_keystore.sh
```

It creates `android/billbox-release.jks` and `android/keystore.properties` (never committed) and prints four values.
On GitHub: **Settings › Secrets and variables › Actions › New repository secret**, add:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the long text it printed (also on the clipboard) |
| `ANDROID_KEYSTORE_PASSWORD` | the password it printed |
| `ANDROID_KEY_ALIAS` | `billbox` |
| `ANDROID_KEY_PASSWORD` | the password it printed |

Keep `billbox-release.jks` and its password safe (a USB drive or password manager): without them a future version
cannot update BillBox on phones. `./build.sh release` on your Mac signs with the same key.

Without the secrets the release still builds, but its APK is signed with a throw-away key (the release run shows a
warning): it installs on a phone that has no BillBox, but cannot update an earlier one.

An APK you built yourself with `./build.sh` (debug key of your Mac) and one from a release use different keys: back up
(Settings › Backup › Back up now, then Save a copy), uninstall, install the release, and restore the backup.

## Costs

Public repositories build for free. In a private repository GitHub counts minutes (macOS minutes count ten times), so
CI runs on Linux only and the Mac and iPhone are built just for releases.
