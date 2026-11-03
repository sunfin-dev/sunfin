# Contributing to Sunfin

Thanks for wanting to help. Sunfin is a fork of [Moonfin](https://github.com/Moonfin-Client/Moonfin-Core): one Flutter codebase whose main target is Android TV, with phone and Windows builds alongside.

## Before you start

- Search the [issues](https://github.com/sunfin-dev/sunfin/issues) first. Someone may already be on it.
- A fix or feature that is not about Sunfin's look (playback, downloads, server support, settings) usually belongs in Moonfin first, so both projects get it. Sunfin then picks it up when it merges upstream.
- For a change to the TV look, describe what you want and how it should behave with a remote before writing code.

## Making a change

1. Fork the repository and branch from `main`.
2. Keep each pull request to one change, with tests where the code is testable.
3. Run `dart analyze lib test packages/design` and `flutter test` before you open the pull request.
4. Try TV changes with a D-pad (an Android TV device, or the Windows build with the arrow keys). Every screen must be usable without a pointer.

## License

By contributing you agree that your work is licensed under the GNU General Public License v2.0, like the rest of the project.
