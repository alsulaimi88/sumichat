# Releasing SumiChat

A release is signed with your Apple Developer ID and notarized by Apple, so it
opens on any Mac with no "unidentified developer" warning.

## One-time setup

### 1. Join the Apple Developer Program

Sign up at <https://developer.apple.com/programs/enroll/> with your Apple ID.
It costs US$99 a year. Approval can take a day or two.

### 2. Create your two Developer ID certificates

1. Open **Xcode → Settings → Accounts** and add your Apple ID if it isn't listed.
2. Select your team and click **Manage Certificates…**
3. Click **+** and choose **Developer ID Application**.
4. Click **+** again and choose **Developer ID Installer**.

Both are now in your keychain. Check with:

```bash
security find-identity -v
```

You should see one line starting `Developer ID Application:` and one starting
`Developer ID Installer:`.

### 3. Save your notarization login

1. At <https://account.apple.com>, go to **Sign-In and Security → App-Specific Passwords**
   and create one called "SumiChat notary".
2. Find your Team ID at <https://developer.apple.com/account> under **Membership details**.
3. Run this and type the app-specific password when asked:

```bash
xcrun notarytool store-credentials sumichat-notary --apple-id "you@example.com" --team-id "ABCDE12345"
```

The password is saved in your keychain. You won't need it again.

### 4. Back up the update signing key

`build.sh` downloads [Sparkle](https://sparkle-project.org), which installs updates. Every
update is signed with a private key kept in your keychain (account `sumichat`, created
with `vendor/Sparkle-*/bin/generate_keys --account sumichat`). Its public half is
`SUPublicEDKey` in `Resources/Info.plist`.

**If you lose this key, installed copies can't be updated anymore.** Export it once and
keep it in your password manager:

```bash
vendor/Sparkle-*/bin/generate_keys --account sumichat -x sumichat-update-key.txt
```

Then delete the exported file from disk.

## Each release

1. Raise the version in `Resources/Info.plist`: `CFBundleShortVersionString`
   (for example `1.1` → `1.2`) and `CFBundleVersion` (`2` → `3`). Sparkle uses
   `CFBundleVersion` to tell which is newer, so it must go up every time.
2. Commit your changes.
3. Run:

```bash
./release.sh --publish
```

This builds the app for Apple silicon and Intel, signs it, sends it to Apple
for notarization (a few minutes), packages the `.pkg` and `.dmg`, notarizes
those too, checks them with Gatekeeper and uploads them to a new GitHub
release, then adds the release to the update feed (`docs/appcast.xml`) and pushes
it. The website's download buttons always point at the latest release, and
installed copies offer the update within a day.

Leave out `--publish` to make the signed files in `dist/` without uploading them.
