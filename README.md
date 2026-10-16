# Shiro 0.4.0

A personal AI workspace with local models, custom bots, and a Linux computer for tools.

## Downloads

Use the release assets for the native Mac app or the Windows/Linux portable previews. Windows/Linux binaries are unverified previews until tested on those operating systems. The portable Docker computer is experimental and has not been validated end to end.

Native Mac 0.4.0 adds shared semantic memory, session checkpoints, bounded context recovery, source-bound CV creation and independent per-file review. See [memory and harness](docs/MEMORY-HARNESS.md) for behavior, privacy and limitations.

## Build native Mac

On macOS 14+ with Swift Command Line Tools: `scripts/build.sh`. This produces `dist/Shiro.app` for the host architecture. Verify with `swift run ShiroChecks` and `python3 scripts/test_guest.py`. The published binary is Apple silicon; Intel users can build locally.

For local inference, install Ollama or connect a compatible local server. For tools, install Lima and create the Linux computer in Shiro. No model weights or VM image are bundled. The native app is ad-hoc signed, not Apple-notarized. See [distribution and permissions](docs/DISTRIBUTION.md).

## Build portable

Install Node.js 22.12+. In `portable`: `npm ci`, `npm test`, `npm start`. Package with `npm run package:windows` or `npm run package:linux`. This edition has local-model chat, bot memory, custom characters, file tools and an experimental Docker computer. Cloud adapters, routines, native model loaders, AI repair and inter-bot delegation remain native Mac features. The editions have separate profiles.

Read [the portable guide](portable/README.md) for Docker setup, platform-specific instructions and limitations. Electron is MIT-licensed; its notices remain in the binary archives. Project source is supplied for review and building; no open-source license grant is implied.

## Privacy

Release archives contain application code and runtime resources, not developer chats, keys, models, attachments or browser profiles. Native settings stay under ShiroLocal; portable data uses a separate ShiroPortable profile. Tool execution uses the Linux computer, not a fallback host shell. Isolation does not guarantee protection from every exploit or network access.
