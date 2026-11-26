# Internal TestFlight builds

The owner installs drafts of the app on an iPad through TestFlight, without access to the Mac that
builds them. Builds come from any clean, pushed branch, each upload needs the owner's consent, and
they are never submitted or published.

## Rules

- Each upload needs the owner's explicit consent for that build; consent for one build does not
  cover the next.
- The source is a clean commit pushed to origin, on any branch.
- Never submit, publish or tag such a build, and never select it for an App Store version.
- TestFlight notifies the testers itself when a build is ready; no other message is needed.

## Steps

1. Check out the source commit and push it if it is not on origin.
2. Run in that checkout, with a note that tells the testers what to try:

   ```sh
   scripts/testflight-internal.py --dry-run
   scripts/testflight-internal.py --notes "<what to test>"
   ```

   The script archives with the chosen version and the next app-wide build number, uploads the
   build as internal-only, waits for Apple's processing, sets export compliance and the note, and
   waits until the tester group can install the build.
3. Report the version, the build number, the source branch and the commit.

Logs and the archive are under the ignored `.build/testflight/<version>-<build>/` of the checkout.
`scripts/testflight-internal.py --help` lists the options.

## Setup

- **App record.** The app exists in App Store Connect, and `Config/Local.xcconfig` carries its
  bundle identifier and team (see [development.md](development.md)). App records are created on
  the App Store Connect website; the API cannot create them.
- **Tester group.** The app has an internal TestFlight group with access to all builds, so a new
  build reaches the group without being assigned. The script looks for a group named "Intern";
  `--group` selects another. Internal testers are App Store Connect users of the team.
- **API key.** `~/.config/app-store-connect/config.json` names an App Store Connect API key that may
  upload builds: `{"key_id": "…", "issuer_id": "…", "key_path": "…"}`. The key signs the archive
  and the API requests. It stays outside the repository.

A tester installs the TestFlight app, accepts the invitation once and is then notified of every new
build. Installing a build replaces the previous one and keeps its data.

## Versions and build numbers

- Builds are exported with `testFlightInternalTestingOnly`, so App Store Connect rejects them for
  App Review and external testing.
- The marketing version is the one in `Config/Lined.xcconfig` while App Store Connect still accepts
  builds for it. Once that version is in review or released, it is the next patch after the
  highest such version.
- Build numbers rise across all versions of the app: every upload takes the highest uploaded build
  number plus one. `--print-next-build` prints it.
- Version and build number are passed to `xcodebuild` and never committed.
- TestFlight builds expire after 90 days.
