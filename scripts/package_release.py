#!/usr/bin/env python3
"""Package only explicit release inputs. Never archive the whole developer workspace."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, tarfile, zipfile, tempfile
parser=argparse.ArgumentParser();parser.add_argument("--native-only",action="store_true");args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1]
VERSION=(ROOT/'VERSION').read_text().strip()
OUT=ROOT/'releases/downloads';OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'releases/source'/('Shiro-'+VERSION)
if SOURCE.exists():shutil.rmtree(SOURCE)
SOURCE.mkdir(parents=True)
for name in ['Package.swift','VERSION']:
 shutil.copy2(ROOT/name,SOURCE/name)
for folder in ['Sources','Tests']:
 shutil.copytree(ROOT/folder,SOURCE/folder,ignore=shutil.ignore_patterns('__pycache__','*.pyc','.DS_Store'))
(SOURCE/'scripts').mkdir()
for name in ['build.sh','Info.plist','make_icon.swift','install_guest.py','test_guest.py','test_harness.py','test_live_local.py','package_release.py']:
 shutil.copy2(ROOT/'scripts'/name,SOURCE/'scripts'/name)
shutil.copytree(ROOT/'portable',SOURCE/'portable',ignore=shutil.ignore_patterns('node_modules','__pycache__','*.pyc','.DS_Store'))
shutil.copytree(ROOT/'.github',SOURCE/'.github')
(SOURCE/'docs').mkdir()
for name in ['DISTRIBUTION.md','MEMORY-HARNESS.md','LOCAL-MODEL-CHOICES.md']:
 shutil.copy2(ROOT/'docs'/name,SOURCE/'docs'/name)
readme=f'''# Shiro {VERSION}

A personal AI workspace with local models, custom bots, and a Linux computer for tools.

## Downloads

Use the release assets for the native Mac app or the Windows/Linux portable previews. Windows/Linux binaries are unverified previews until tested on those operating systems. The portable Docker computer is experimental and has not been validated end to end.

Native Mac 0.4.1 adds shared semantic memory, session checkpoints, bounded context recovery, source-bound CV creation and independent per-file review. See [memory and harness](docs/MEMORY-HARNESS.md) for behavior, privacy and limitations.

## Build native Mac

On macOS 14+ with Swift Command Line Tools: `scripts/build.sh`. This produces `dist/Shiro.app` for the host architecture. Verify with `swift run ShiroChecks` and `python3 scripts/test_guest.py`. The published binary is Apple silicon; Intel users can build locally.

For local inference, install Ollama or connect a compatible local server. For tools, install Lima and create the Linux computer in Shiro. No model weights or VM image are bundled. The native app is ad-hoc signed, not Apple-notarized. See [distribution and permissions](docs/DISTRIBUTION.md).

## Build portable

Install Node.js 22.12+. In `portable`: `npm ci`, `npm test`, `npm start`. Package with `npm run package:windows` or `npm run package:linux`. This edition has local-model chat, bot memory, custom characters, file tools and an experimental Docker computer. Cloud adapters, routines, native model loaders, AI repair and inter-bot delegation remain native Mac features. The editions have separate profiles.

Read [the portable guide](portable/README.md) for Docker setup, platform-specific instructions and limitations. Electron is MIT-licensed; its notices remain in the binary archives. Project source is supplied for review and building; no open-source license grant is implied.

## Privacy

Release archives contain application code and runtime resources, not developer chats, keys, models, attachments or browser profiles. Native settings stay under ShiroLocal; portable data uses a separate ShiroPortable profile. Tool execution uses the Linux computer, not a fallback host shell. Isolation does not guarantee protection from every exploit or network access.
'''
(SOURCE/'README.md').write_text(readme)
(SOURCE/'.gitignore').write_text('node_modules/\n.build/\ndist/\nreleases/\n.DS_Store\n.env\n*.log\n__pycache__/\n')
# Repository-ready source stays separate from the developer checkout.
zip_path=OUT/f'Shiro-{VERSION}-source.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(SOURCE.rglob('*')):
  if p.is_file():z.write(p,Path('Shiro-'+VERSION)/p.relative_to(SOURCE))
mac=OUT/f'Shiro-{VERSION}-mac-arm64.zip'
subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(ROOT/'dist/Shiro.app'),str(mac)],check=True)
portable_version=json.loads((ROOT/'portable/package.json').read_text())['version']
if not args.native_only:
 win=ROOT/'releases/portable/Shiro-Portable-win32-x64'
 shutil.make_archive(str(OUT/f'Shiro-Portable-{portable_version}-windows-x64'),'zip',win.parent,win.name)
 linux=ROOT/'releases/portable/Shiro-Portable-linux-x64'
 with tarfile.open(OUT/f'Shiro-Portable-{portable_version}-linux-x64.tar.gz','w:gz') as t:t.add(linux,arcname=linux.name)
archives=[zip_path,mac]+[p for p in [OUT/f'Shiro-Portable-{portable_version}-windows-x64.zip',OUT/f'Shiro-Portable-{portable_version}-linux-x64.tar.gz'] if p.exists()]
checks=''.join(hashlib.file_digest(p.open('rb'),'sha256').hexdigest()+'  '+p.name+'\n' for p in archives)
(OUT/'SHA256SUMS.txt').write_text(checks)
manifest={'version':VERSION,'mac':{'architecture':'arm64','status':'native release; tested on macOS'},'windows':{'version':portable_version,'architecture':'x64','status':'unverified portable preview'},'linux':{'version':portable_version,'architecture':'x64','status':'unverified portable preview'},'computer_preview':'Docker computer not end-to-end tested','files':[{'name':p.name,'bytes':p.stat().st_size} for p in archives]}
(OUT/'release-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for p in archives:print(p.name,round(p.stat().st_size/1024/1024,2),'MiB')
print('Source staged at',SOURCE)
