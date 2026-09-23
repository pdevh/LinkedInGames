# Updating LinkedInGames

The macOS app uses Sparkle 2.9.6. It checks the GitHub Releases appcast in the
background and asks before downloading and installing an update. Users can
also choose **LinkedInGames → Check for Updates…** or turn automatic checks
off in the same menu. The app never installs updates without a prompt.

The feed is `https://github.com/pdevh/LinkedInGames/releases/latest/download/appcast.xml`.
Each GitHub release must contain both `appcast.xml` and its signed
`LinkedInGames-VERSION.zip`. The appcast and archive are signed with Sparkle's
Ed25519 key. The matching public key is embedded in `Info.plist` by `build.sh`.
The private key is in the macOS Keychain under account `LinkedInGames`; it is
never stored in this repository.

## Prepare a release

1. Set a new semantic version and a **strictly increasing** integer build
   number. The first updater-enabled build uses `2.1.0` / `5`; the old build
   was `2.0.1` / `4`.
2. Run on the Mac holding the signing key:

   ```sh
   ./prepare-release.sh 2.1.0 5
   ```

   Optional: set `CODE_SIGN_IDENTITY='Developer ID Application: …'` to sign
   with a Developer ID identity and `RELEASE_NOTES_FILE=/path/to/notes.md` to
   embed release notes. This script builds the app, verifies the Keychain
   public key against the app, creates a zip, and signs both the archive and
   appcast. Assets are placed in `.build/releases/v2.1.0/`.
3. Inspect the appcast and verify the app bundle:

   ```sh
   codesign --deep --verify --strict LinkedInGames.app
   plutil -p LinkedInGames.app/Contents/Info.plist
   ```

4. Publish a public GitHub release tagged `v2.1.0` with **both** assets:

   ```sh
   gh release create v2.1.0 \
     .build/releases/v2.1.0/LinkedInGames-2.1.0.zip \
     .build/releases/v2.1.0/appcast.xml \
     --title 'v2.1.0' --notes-file /path/to/notes.md
   ```

   Omit `--notes-file` if no notes are available; `gh release create` then
   needs another notes option such as `--generate-notes`. Do not edit the
   generated appcast after signing it. Confirm that the `latest/download`
   links return the published assets.

For subsequent releases, use a new version and larger build number. Sparkle
compares `CFBundleVersion` to detect updates. A release without the appcast is
invisible to the updater. The appcast URL points at GitHub's latest *stable*
release, so do not publish a newer unrelated release without these assets.

## Signing and distribution

The current local build is ad hoc code signed. Sparkle's Ed25519 signature
authenticates updates, and signed feeds authenticate update metadata. Sparkle
does not strictly require a Developer ID certificate for this path. Developer
ID signing and notarization are strongly recommended for public distribution:
they reduce Gatekeeper friction and give users Apple's identity checks.
Notarization requires an Apple Developer account and is a separate step before
publishing the archive. Keep the bundle identifier `local.philipp.zipgame` and
sign all future releases consistently. Never rotate the Sparkle key casually;
ad hoc builds cannot rely on Developer ID fallback if it is lost.

To inspect the existing Keychain public key:

```sh
.build/sparkle-2.9.6/bin/generate_keys --account LinkedInGames -p
```

Back up the private key securely before relying on updates. Sparkle documents
`generate_keys --account LinkedInGames -x /secure/path` for an export; store
that file outside the repository. On a new release Mac, import it with
`generate_keys --account LinkedInGames -f /secure/path`. Never commit or paste
the export.

To verify an end-to-end update, install an older updater-enabled release and
publish a newer signed release. The prior `2.0.1` build has no updater, so it
cannot self-update. Check the menu action and background prompt on the older
Sparkle-enabled build, then inspect its installed version after relaunch.

Sparkle references: [integration](https://sparkle-project.org/documentation/),
[publishing](https://sparkle-project.org/documentation/publishing/).
