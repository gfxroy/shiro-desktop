# Shiro distribution: Mac 0.3.1, portable 0.2.0

## Download choices

- **Mac native:** Apple silicon, macOS 14 or later. The app is ad-hoc signed, not notarized. This is the recommended Mac edition.
- **Windows portable preview:** Windows 11 x64 ZIP. Cross-packaged with Electron; not yet tested on Windows. Unsigned.
- **Linux portable preview:** Linux desktop x64 tar.gz, targeting Ubuntu 24.04 or later. Cross-packaged; not yet OS-tested.
- **Buildable source:** Native Swift source, portable Electron source, pinned JavaScript dependencies, computer resources, checks and packaging scripts.

The portable UI was exercised on macOS with a deterministic HTTP model fixture. That verifies discovery, IPC, persistence and a chat round trip; it is not a real model or Windows/Linux runtime test. Its core tests cover endpoint restrictions, workspace paths, streamed tool arguments, truncation rejection, HTTP failure handling, state persistence and stdin execution. Docker is unavailable on this build host, so its experimental Linux computer has not been validated end to end. This limitation is disclosed on the website and in release notes.

## Build native Mac

Install Apple Command Line Tools or Xcode and use macOS 14 or later:

```sh
scripts/build.sh
swift run ShiroChecks
python3 scripts/test_guest.py
```

The native binary matches the machine architecture. The published Mac artifact is arm64. Intel users can build the source on an Intel Mac. Lima and model runtimes are separate runtime dependencies, not build dependencies.

## Build portable

Install Node.js 22.12 or later. From portable:

```sh
npm ci
npm test
npm run package:windows
npm run package:linux
```

Native target builds are preferable; cross-packaging assembles a target Electron runtime but does not exercise it on that OS. The GitHub build workflow runs the same tests and packaging on Windows and Linux runners, without claiming interactive desktop or Docker validation. See portable/README.md for features, limitations and data locations.

## Permissions and trust

Native Mac controls a Linux VM, so host Accessibility, Screen Recording, microphone, camera and Full Disk Access permissions are not needed for its computer tools. Native file dialogs grant access to selected files. The portable computer uses Docker and a private named volume, with no host folder or Docker-socket mount. Docker itself is privileged software; review its supported installation and licensing.

Unsigned/notarization warnings are expected. Verify checksums and source before making an exception for this app. Use the official per-app OS flow; never disable Gatekeeper, antivirus or Electron's renderer sandbox globally. Apple instructions: https://support.apple.com/102445 . Model downloads, cloud providers and browser research need network access; downloaded local inference can work offline.

## Release packaging

Run `python3 scripts/package_release.py` after producing the native app and both portable target directories. For a native-only update, use `--native-only` to keep the existing portable archives unchanged. It creates archives and SHA256SUMS.txt under releases/downloads. Source packaging uses an explicit file allowlist; it excludes conversations, profiles, model weights, credentials, research captures, app backups and local build caches. No personal runtime data is part of the public release.

Native Mac 0.3.1 adds [shared memory and the completion harness](MEMORY-HARNESS.md). Portable previews remain 0.2.0 and do not include these native features.
