# Changelog

Sunfin's version numbers count up from 0.1.0, where the fork began: a small change adds 0.0.1, a bigger one raises the middle number and starts the last at 1 again. Sunfin stays below 1.0 until it is ready for everyone.

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
