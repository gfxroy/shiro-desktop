# Shiro Portable 0.2.0 — preview

A desktop preview for Windows, Linux and macOS, built with Electron. Windows and Linux artifacts are **cross-packaged, not yet tested on those operating systems**. The native Mac app is the recommended Mac release. These are separate interfaces and profiles, not full feature parity.

## What works in this edition

- Local OpenAI-compatible model connections, installed-model discovery, bounded streaming replies and cancellation.
- Separate bot instructions, memory and chats; nine character shapes, color and pointer tracking.
- A shared Linux computer built locally with Docker, using the same guest browser/file/shell tools as native Shiro.
- File browsing, selected-file import, download/export and computer expansion in the app window.
- Explicit approval for shell commands, file writes, browser clicks and input. Read tools do not require approval.

Cloud provider adapters, scheduled routines, native model-file loaders, PDF attachment text extraction, AI repair and inter-bot delegation are not implemented in this preview. PDF generation is available inside the computer via installed tools, but the model tool list currently exposes text file writes rather than a dedicated PDF command. Model weights, Docker and the computer image are not bundled.

## Run a downloaded package

**Windows:** Use Windows 11 x64. Extract the entire ZIP, then run `Shiro-Portable.exe` from the extracted directory. Keep its supporting files together. The preview is not Authenticode-signed. Windows may display an unknown-publisher warning. Verify the release checksum and trust the publisher before running it. Never disable Windows Defender globally. For computer tools, install and start Docker Desktop with its supported WSL 2 backend; follow Docker's own installation prompts.

**Linux:** Use a current x64 desktop distribution such as Ubuntu 24.04+. Extract the `.tar.gz` and run `./Shiro-Portable` from that folder as your normal user. Keep supporting files together. Chromium/Electron needs a working desktop and sandbox support; the exact distribution configuration is unverified. If sandbox errors occur, use your distribution's supported Electron sandbox configuration. Do not run the app as root or disable the Electron sandbox. Install Docker Engine using your distribution's supported configuration; the app must be able to call Docker without an interactive sudo prompt.

**Mac portable source:** Use Node.js 22.12+ and macOS 14+. The native Swift app is the recommended Mac download. Building this preview does not replace native Shiro or migrate its saved data.

## Connect a model

1. Install and start [Ollama](https://ollama.com/download), or another loopback OpenAI-compatible server.
2. Download a model, for example `ollama pull qwen3.5:4b`. We suggest 16 GB RAM for this model plus the 3 GB computer. For a lighter machine, try `qwen3.5:2b`.
3. Open **Models & setup**, set `http://127.0.0.1:11434/v1`, fetch installed models and save your selection.
4. Chat without setting up the computer, or open **Workspace → Set up computer** for tools.

Only loopback endpoints are accepted. Local models containing `cloud` in their identifier are rejected. Qwen thinking is off by default through Ollama and can be enabled. LiteRT-LM endpoints require the LiteRT checkbox for its token parameter; the preview does not install that runtime.

## Computer and permissions

Docker builds a Debian Linux desktop on first setup; this needs internet access, several GB of disk and time. The container gets two CPU cores and a 3 GB memory limit. Its desktop is exposed only on a dynamically assigned loopback port with a generated VNC password. No host directory, host Docker socket, SSH key or cloud API key is mounted. Its private named volume persists files and browser profile; the container has network access. Chromium inside the container runs without its inner sandbox because of the container restrictions; Electron's host renderer sandbox remains enabled. Container isolation is not a guarantee against every exploit or network access.

The app calls Docker as the current user; this grants the app whatever Docker access that user already has. Docker itself is a privileged dependency. Install it only from its official source and review Docker Desktop's licensing. The preview never falls back to running model commands on the host. Use native file dialogs to attach or save individual files. No host Accessibility, Screen Recording, microphone, camera or Full Disk Access permission is required for the container desktop.

Closing the app cancels its active model request but leaves the container running, so files and desktop remain available. To stop it explicitly, use `docker stop shiro-portable-v020`. Do not remove the `shiro-portable-home` volume unless you intend to erase its computer files and browser profile.

## Build from source

Install Node.js 22.12 or later and use a terminal in this folder:

```sh
npm ci
npm test
npm start
```

Package using the current target OS where possible:

```sh
npm run package:windows
npm run package:linux
npm run package:mac
```

`@electron/packager` also supports cross-packaging; this assembles the correct Electron runtime but does not test the application on that OS. Outputs go to `../releases/portable`. Package version and runtime dependencies are pinned in package.json/package-lock.json. Docker is needed only for computer tools, not for building the Electron shell or plain chat.

Saved portable data lives in a separate `ShiroPortable` folder under the OS application-data directory. Native Mac data stays under `ShiroLocal`. There is no automatic migration between editions. Source builds and binaries are unsigned previews; reproducible builds do not imply publisher signing or notarization. Electron's license and third-party notices remain included with packaged distributions.
