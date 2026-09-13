# REYDL

REYDL is an iOS download manager with a Safari Web Extension plus an in-app WKWebView browser.

## Core behavior

- Safari extension detects explicit download links and common file URLs, then attempts a `reydl://` handoff to the containing app.
- In-app browser captures `download` links, common file links, `Content-Disposition: attachment` responses, and MIME types WebKit cannot display.
- Background `URLSession` engine persists transfers while iOS suspends the UI app.
- HTTP byte-range capable servers use an adaptive 2–64 segment engine. The queue itself has no artificial file-count limit.
- Pause/resume uses task suspension plus persisted transfer state. Completed range parts are preserved and joined in order.
- Servers without byte-range support automatically fall back to a normal background download.
- Completed files live in `Documents/REYDL Downloads` and can be shared/exported.

## iOS limitation

iOS does not expose a supported API that lets a third-party app universally replace Safari's built-in download manager. The Safari extension therefore uses best-effort user-gesture handoff, while the built-in browser is the reliable capture path.

## Build

The repository workflow `build-reydl-ipa.yml` installs XcodeGen, generates the Xcode project, builds an unsigned device app, verifies the Safari extension is embedded, and uploads `REYDL-unsigned.ipa` as a GitHub Actions artifact.
