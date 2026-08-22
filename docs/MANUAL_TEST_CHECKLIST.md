<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Manual Test Checklist

Use this checklist on a clean supported Windows x64 installation for a release candidate. Automated/static checks remain mandatory; this list covers behavior that should be observed in the exported application.

## Startup and shell

- [ ] The application starts from the packaged `dist/` directory without relying on developer-machine paths.
- [ ] Hub, board creation/opening, settings, About, Credits, and Resource Library open without visible errors.
- [ ] Text in About/Credits is readable in the current theme.
- [ ] HTTP(S) links in About are visibly interactive and open in the system browser; non-HTTP(S) metadata is not opened.

## Boards and portable data

- [ ] Create, save, reopen, rename, and delete a test board.
- [ ] Add representative text, drawing, connector, image, audio, video, PDF, note, and module objects supported by the build.
- [ ] Export and re-import a `.notlight-board` package and compare content/state.
- [ ] Reject a deliberately malformed portable package without writing payload outside the intended destination.

## Resource Library and media

- [ ] Import representative image, audio, video, and PDF assets.
- [ ] Confirm Library-backed background audio can be selected and remains referenced while configured.
- [ ] Play foreground audio/video/voice media and confirm background music ducks and returns correctly.
- [ ] Verify PDF metadata/page rendering and thumbnails.
- [ ] If qpdf optimization is enabled, create an optimized PDF variant and confirm the original remains available.

## Formula rendering

- [ ] Render representative inline/display formulas with the bundled Typst/MiTeX stack while offline.
- [ ] Confirm missing/invalid formula input reports an error without corrupting the note/board.

## Localization and dialogs

- [ ] Switch among bundled locales and inspect Hub, Settings, About, Credits, Library, and representative board toolbars.
- [ ] Verify About GitHub link opens correctly.
- [ ] After replacing the Telegram placeholder with a full `https://t.me/...` URL, verify it is linkified and opens correctly.

## Runtime sidecars

- [ ] Run `CHECK_WINDOWS_EXPORT.bat` successfully from the assembled release.
- [ ] FFmpeg/ffprobe report the pinned expected version/build.
- [ ] Poppler `pdfinfo`/`pdftoppm`, qpdf, and Typst execute from packaged paths.
- [ ] Test on a machine with the supported Microsoft Visual C++ Redistributable x64 installed and no developer-only runtime directories on `PATH`.

## Release/compliance gate

- [ ] Run `python tools/validate_release_compliance.py` on the clean source tree.
- [ ] Resolve every item identified by `python tools/validate_release_compliance.py --public-release` before claiming a redistributed binary archive is compliance-reviewed.
- [ ] Confirm `.godot/`, caches, build directories, user data, and undocumented audio are absent from the source-release tree.
- [ ] Regenerate and verify `FILE_CHECKSUMS.sha256` only after the final release-source change.
- [ ] Confirm the exact license/notices and corresponding-source arrangement match the exact binaries being distributed.
