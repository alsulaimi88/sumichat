<p align="center"><img src="docs/icon.png" width="128" alt="SumiChat icon"></p>

# SumiChat

A Mac app that shows WhatsApp Web in its own window and downloads every file
people send you, PDFs included.

- Downloads **any** file type (PDFs, documents, spreadsheets, photos, voice notes) straight to `~/Downloads`
- Shows macOS notifications for new messages, with a **Reply** box (click one to jump to the chat)
- Several accounts side by side (**File → New Account…**), each with its own window and login (macOS 14+)
- Puts the unread count on the Dock icon and in the window title
- Lets you attach files and record voice notes
- Stays signed in between launches; closing the window keeps it running in the Dock
- Updates itself with one click, through [Sparkle](https://sparkle-project.org)

Runs on Apple silicon and Intel Macs with macOS 13 or later.

## Build

```bash
./build.sh            # builds build/SumiChat.app
./build.sh install    # also copies it to /Applications
./package.sh          # makes dist/SumiChat.pkg and dist/SumiChat.dmg for testing
```

Needs Xcode (or the Command Line Tools).

## Release

`./release.sh --publish` signs the app with a Developer ID, has Apple notarize
it, and uploads the installer and disk image to GitHub. See
[RELEASING.md](RELEASING.md) for the one-time setup.

The website in [`docs/`](docs/index.html) is served by GitHub Pages.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘R | Reload |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / reset |
| ⌥⌘L | Open Downloads folder |
| ⌘1 | Show the window |
| ⌃⌘F | Full screen |

## License

[MIT](LICENSE): free to use, change and share, as long as the copyright notice stays.

## Disclaimer

SumiChat is an independent app. It isn't affiliated with, endorsed or
sponsored by WhatsApp or Meta. WhatsApp is a trademark of WhatsApp LLC.
