# Google Drive backups

BillBox (Mac, iPhone and Android) can upload every backup into a folder called **BillBox Backups** in your Google
Drive, besides the copy kept on the device. Each backup becomes its own folder in there
(`FMCG_Backup_YYYYMMDD_HHMMSS`), holding the same files as on the device, so it restores on any of the three apps.

BillBox asks Google only for the `drive.file` permission: it can see and change **only the files it made itself**,
never the rest of your Drive.

## One-time setup: your own Google keys (about 5 minutes, free)

BillBox has no server of its own, so it signs in to Google with a key you make in your own Google account.

1. Open <https://console.cloud.google.com> with the Gmail account whose Drive should hold the backups.
2. At the top, **Select a project › New project**, name it `BillBox`, **Create**, and select it.
3. **APIs & Services › Library**, search **Google Drive API**, open it, **Enable**.
4. **APIs & Services › OAuth consent screen** (or *Google Auth Platform › Branding*): **Get started**,
   app name `BillBox`, your email for support and contact, audience **External**, **Create**.
   Then under **Audience › Test users** press **Add users** and add your Gmail address.
5. **APIs & Services › Credentials › Create credentials › OAuth client ID**.
   Application type: **TVs and Limited Input devices**. Name `BillBox`. **Create**.
6. Press **Download JSON** (the file is called `client_secret_….json`). In BillBox use **Import the downloaded JSON file…**; or copy the **Client ID** (ends in `.apps.googleusercontent.com`) and the **Client secret** by hand. A client made a minute ago can take a few minutes before Google knows it ("The OAuth client was not found").

While the app stays in "Testing", Google asks you to sign in again about once a week. To avoid that, on the
**Audience** page press **Publish app** (for your own use no review is needed for the `drive.file` permission;
Google may show "unverified app" during sign-in: choose *Advanced › Go to BillBox*).

## Connect

Settings › Backup › **Google Drive**:

1. **Import the downloaded JSON file…** (or paste the Client ID and secret and press **Save keys**).
2. **Connect Google Drive**. BillBox shows a code like `ABCD-EFGH`.
3. On any phone or computer open <https://www.google.com/device>, enter the code, choose your account and allow BillBox.
4. BillBox notices by itself within a few seconds and makes **BillBox Backups** in your Drive.

From then on **Back up now**, the daily backup and the backup on quitting are uploaded too (in the background; the
result shows as "Last upload" on the same screen). **Upload the newest backup now** sends the latest one again.
**Disconnect** stops uploading; nothing already in Drive is removed.

The keys are kept with the company list, so one setup covers every company in that app. Each app (Mac, iPhone,
Android) is connected separately, with the same keys.

## Restoring from Drive

Download the backup folder from drive.google.com (Drive zips it), then Settings › Backup ›
**Restore from a backup folder or .zip…**.
