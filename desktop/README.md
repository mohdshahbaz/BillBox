# BillBox for Linux and Windows

The desktop app is the Flutter app in `frontend/` with the books engine beside it: Node.js 22 (SQLite is built in) running
`backend/src`, the same engine as the Mac app, so figures, bills and backups are the same on every BillBox.

```
BillBox/                      (Windows: C:\Program Files\BillBox)
├── billbox | BillBox.exe     the app
├── engine/node | node.exe    Node.js 22
└── engine/backend/src/       the books engine (server.js)
```

On start the app runs the engine on 127.0.0.1 (port 37420, or the next free one) with the books in
`~/.local/share/BillBox` (Linux) or `%APPDATA%\BillBox` (Windows); backups go to `…/BillBox/Backups` until another folder
is chosen. The engine stops by itself when the app closes.

## Build

GitHub builds both on every push that touches them (Actions › Desktop) and puts them on each release. By hand, on the
matching system with Flutter and Node 22:

```bash
desktop/build.sh linux 15.8.0      # dist/BillBox-linux-15.8.0-x64.tar.gz and .deb
desktop/build.sh windows 15.8.0    # dist/BillBox-windows-15.8.0-x64.zip and -setup.exe (Inno Setup), from Git Bash
EDITION=admin desktop/build.sh linux 15.8.0-admin   # the admin / test licence edition
```

## What it has

Look (docs/DESIGN_SYSTEM.md): Material 3 with the design-system colours and spacing, light and dark mode and the same
themes as the iPhone and Mac (Settings › Appearance), a dark navigation sidebar with Ctrl+1…9 shortcuts, tables that sort
by a click on a heading, status pills and summary cards, and the window title "BillBox — <company>".

Dashboard, billing (batches, schemes, credit limits), purchases (with supplier-bill PDF import), all bills, stock,
parties and ledgers, salesmen and beats, books and GST reports with Excel export, printing (half sheet / A4), backups to a
folder with restore, and Google Drive backups with restore. Screens the Mac and iPhone have that the desktop app does not
have yet: debit notes, Marg import, e-way bill JSON, WhatsApp sending and the Marg bill design — the engine already does
all of them, so they are being added screen by screen.
