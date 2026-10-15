#!/usr/bin/env python3
"""Install Shiro's guest user and desktop in a caller-selected Lima VM."""
import base64
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
if len(sys.argv) != 2 or not sys.argv[1].replace("-", "").replace("_", "").isalnum():
    raise SystemExit("Usage: python3 scripts/install_guest.py VM_NAME")
name = sys.argv[1]
# The Swift installer applies the same mount/SSH/VZ checks from the app.
import json
inventory = subprocess.check_output(["limactl", "list", "--json"], text=True)
info = next((json.loads(line) for line in inventory.splitlines() if json.loads(line)["name"] == name), None)
if not info or info["vmType"] != "vz" or info["config"].get("mounts") or info["config"]["ssh"].get("forwardAgent") is not False or info["config"]["ssh"].get("loadDotSSHPubKeys") is not False:
    raise SystemExit("VM must use VZ with no host mounts or SSH credential forwarding")
encoded = base64.b64encode((ROOT / "Sources/Shiro/Resources/guest.py").read_bytes()).decode()
unit = '''[Unit]
Description=Shiro local desktop
After=network.target
[Service]
User=shiro-local
Environment=HOME=/home/shiro-local
Environment=DISPLAY=:88
ExecStart=/usr/bin/xvfb-run -n 88 -f /home/shiro-local/.Xauthority -s "-screen 0 1280x800x24 -nolisten tcp" /usr/bin/dbus-run-session /usr/bin/openbox-session
Restart=always
[Install]
WantedBy=multi-user.target
'''
installer = f'''
import base64,pathlib,subprocess,shutil
for name in ['Xvfb','openbox','xdotool','scrot','chromium']:
    if not shutil.which(name): raise RuntimeError('Missing desktop dependency: '+name)
import websocket
import importlib.util,os
if any(importlib.util.find_spec(module) is None for module in ['reportlab','openpyxl','docx']):
    environment=dict(os.environ, DEBIAN_FRONTEND='noninteractive')
    subprocess.run(['apt-get','update','-qq'],check=True,env=environment)
    subprocess.run(['apt-get','install','-y','--no-install-recommends','python3-reportlab','python3-openpyxl','python3-docx','poppler-utils'],check=True,env=environment)
subprocess.run(['useradd','-m','-s','/bin/bash','shiro-local'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
root=pathlib.Path('/opt/shiro-local');root.mkdir(exist_ok=True)
(root/'guest.py').write_bytes(base64.b64decode({encoded!r}));(root/'guest.py').chmod(0o755)
subprocess.run(['install','-d','-o','shiro-local','-g','shiro-local','/home/shiro-local/workspace','/home/shiro-local/.config'],check=True)
pathlib.Path('/etc/systemd/system/shiro-local-desktop.service').write_text({unit!r})
subprocess.run(['systemctl','daemon-reload'],check=True)
subprocess.run(['systemctl','enable','--now','shiro-local-desktop'],check=True)
print('Shiro desktop installed in {name}')
'''
subprocess.run(["limactl", "shell", name, "--", "sudo", "python3", "-c", installer], check=True)
