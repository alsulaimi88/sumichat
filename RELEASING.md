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

## Each release

1. Raise the version in `Resources/Info.plist`: `CFBundleShortVersionString`
   (for example `1.0` → `1.1`) and `CFBundleVersion` (`1` → `2`).
2. Run:

```bash
./release.sh --publish
```

This builds the app for Apple silicon and Intel, signs it, sends it to Apple
for notarization (a few minutes), packages the `.pkg` and `.dmg`, notarizes
those too, checks them with Gatekeeper and uploads them to a new GitHub
release. The website's download buttons always point at the latest release,
and the app tells people when a new version is out.

Leave out `--publish` to make the signed files in `dist/` without uploading them.
