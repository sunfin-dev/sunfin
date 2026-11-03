# Changelog

Sunfin's version numbers count up from 0.1.0, where the fork began: a small change adds 0.0.1, a bigger one raises the middle number and starts the last at 1 again. Sunfin stays below 1.0 until it is ready for everyone.

## 0.13.1

- **In-app updates.** Sunfin updates itself from its GitHub releases. An update can be installed from the prompt or from *Settings → About → Check for Updates*.
  - Android: Sunfin downloads the APK and opens Android's installer, which asks you to confirm. The first time, Android asks you to allow Sunfin to install apps.
  - Windows: Sunfin downloads the zip, closes, replaces its files and starts again. If Sunfin's folder isn't writable (for example under *Program Files*), the release page opens instead.
  - Every download is checked against the release's `SHA256SUMS.txt` before it is installed.
- **Update check at start.** On every start Sunfin asks GitHub for a newer release and offers it on the home screen. *Cancel* keeps that version quiet for a day.
- **Skip buttons are optional.** The player's skip back and skip forward buttons are hidden by default, since left and right on the remote or keyboard already skip. *Settings → Video Playback → Show skip buttons* brings them back.

## 0.12.5

- License notices: a `NOTICE` file states that Sunfin is a modified version of Moonfin and where the changes are recorded. The licenses of the bundled fonts now ship with the app and appear on the licenses screen.
- The Windows app's file properties name the right copyright holders and the GPL instead of "All rights reserved".
- The Moonfin server plugin entry in Settings uses a generic plugin icon instead of Moonfin's logo.
- Added a security policy, a code of conduct and this changelog.

## 0.12.4

The first release, for Android TV, Android phones and Windows. Forked from Moonfin 2.7.0, it brings:

- A fixed TV look: a slim left rail, a header for the focused title, poster rows, and backdrop art that fades into a page tinted with the art's colours.
- Movie, show and season pages with Play/Resume, a rating line, media chips, season tabs and an episode row.
- Library pages with Recommended and Library tabs, a letter jump bar, and sort and filter menus.
- Settings transfer between devices through your Jellyfin account, and no automatic settings sync.
- Server administration on Windows and phones, for administrators.
- No closed-app push notifications, since those depend on Moonfin's own Firebase project.
