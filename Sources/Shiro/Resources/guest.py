#!/usr/bin/env python3
"""Shiro's unprivileged VM tools. No host execution or host file mounts."""
import base64
import hashlib
import json
import os
from pathlib import Path
import signal
import resource
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

WORKSPACE = Path.home() / "workspace"
CDP = "http://127.0.0.1:9288"
MAX_TEXT = 24000


def required(args, key, kind=str):
    value = args.get(key)
    if not isinstance(value, kind) or (kind is str and not value):
        raise ValueError(f"{key} must be a nonempty {kind.__name__}")
    return value


def run(argv, **kw):
    return subprocess.run(argv, check=True, capture_output=True, timeout=12, **kw)


def workspace_path(value=""):
    if not isinstance(value, str):
        raise ValueError("Path must be a string")
    root = WORKSPACE.resolve()
    supplied = Path(value).expanduser()
    result = supplied.resolve() if supplied.is_absolute() else (root / supplied).resolve()
    if not result.is_relative_to(root):
        raise ValueError("Path escapes the workspace")
    return result


def screenshot():
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "screen.png"
        run(["scrot", str(path)])
        return {"image": base64.b64encode(path.read_bytes()).decode(), "width": 1280, "height": 800}


def browser_tabs():
    try:
        with urllib.request.urlopen(CDP + "/json/list", timeout=3) as r:
            return [x for x in json.load(r) if x.get("type") == "page"]
    except OSError:
        launch_browser()
        for _ in range(30):
            time.sleep(0.3)
            try:
                with urllib.request.urlopen(CDP + "/json/list", timeout=3) as r:
                    return [x for x in json.load(r) if x.get("type") == "page"]
            except OSError:
                pass
        raise RuntimeError("Chromium did not start. Check the VM desktop service.")


def launch_browser():
    subprocess.Popen([
        "chromium", "--user-data-dir=" + str(Path.home() / ".config/shiro-browser"),
        "--remote-debugging-port=9288", "--remote-debugging-address=127.0.0.1",
        "--no-first-run", "--disable-dev-shm-usage", "--window-size=1280,800",
        "--window-position=0,0", "--start-maximized", "about:blank"
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


class Browser:
    def __init__(self):
        import websocket
        tabs = browser_tabs()
        if not tabs:
            raise RuntimeError("Open a browser tab first.")
        self.tab = tabs[0]
        self.ws = websocket.create_connection(self.tab["webSocketDebuggerUrl"], timeout=15, suppress_origin=True)
        self.sequence = 0

    def call(self, method, params=None):
        self.sequence += 1
        self.ws.send(json.dumps({"id": self.sequence, "method": method, "params": params or {}}))
        while True:
            result = json.loads(self.ws.recv())
            if result.get("id") == self.sequence:
                if "error" in result:
                    raise RuntimeError(result["error"].get("message", "Browser error"))
                return result.get("result", {})

    def evaluate(self, expression):
        result = self.call("Runtime.evaluate", {"expression": expression, "returnByValue": True})
        if "exceptionDetails" in result:
            raise RuntimeError("Page evaluation failed; inspect the page and try again.")
        return result.get("result", {}).get("value")

    def loader(self):
        return self.call("Page.getFrameTree").get("frameTree", {}).get("frame", {}).get("loaderId")

    def settle(self, previous=None, expected=None):
        # A new URL can be visible while Chromium still exposes the previous DOM.
        # Match the navigation loader before treating its title/text as evidence.
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            loader = self.loader()
            committed = loader == expected if expected else loader != previous
            if committed and self.evaluate("document.readyState") == "complete":
                return
            time.sleep(0.15)

    def read(self, offset=0):
        if not isinstance(offset, int) or isinstance(offset, bool) or offset < 0:
            raise ValueError("offset must be a nonnegative integer; use nextOffset from the previous read")
        return self.evaluate("""(() => ({url:location.href,title:document.title,
          text:(document.body?.innerText||'').slice(OFFSET,OFFSET+4500),offset:OFFSET,
          nextOffset:(document.body?.innerText||'').length>OFFSET+4500?OFFSET+4500:null,
          links:Array.from(document.querySelectorAll(document.querySelector('#b_results')?'#b_results a[href]':document.querySelector('#search')?'#search a[href]':'a[href]')).filter(e=>e.getClientRects().length&&e.innerText.trim()&&/^https?:/.test(e.href)&&!e.href.endsWith('#'))
            .slice(0,30).map(e=>({text:e.innerText.slice(0,100),url:e.href})),
          fields:Array.from(document.querySelectorAll('input,textarea,button,select')).filter(e=>e.getClientRects().length)
            .slice(0,20).map(e=>({tag:e.tagName,id:e.id,name:e.name,type:e.type,value:e.type==='password'?'[redacted]':(e.value||'').slice(0,120),placeholder:e.placeholder,text:e.innerText?.slice(0,100),selector:(()=>{if(e.id&&document.querySelectorAll('#'+CSS.escape(e.id)).length===1)return '#'+CSS.escape(e.id);if(!e.dataset.shiroControl)e.dataset.shiroControl='control-'+Math.random().toString(36).slice(2);return '[data-shiro-control='+JSON.stringify(e.dataset.shiroControl)+']'})()}))}))()""".replace("OFFSET", str(offset)))

    def close(self):
        self.ws.close()


def browser(args):
    action = required(args, "action")
    if action == "tabs":
        return {"tabs": [{"title": x.get("title"), "url": x.get("url")} for x in browser_tabs()]}
    b = Browser()
    try:
        b.call("Page.bringToFront")
        if action == "navigate":
            url = required(args, "url")
            if urllib.parse.urlparse(url).scheme not in ("http", "https"):
                raise ValueError("Only HTTP and HTTPS navigation is supported")
            navigation = b.call("Page.navigate", {"url": url})
            if navigation.get("errorText"):
                page = b.read()
                page.update({"error": "Navigation failed: " + navigation["errorText"], "requested_url": url})
                return page
            b.settle(expected=navigation.get("loaderId"))
        elif action in ("click", "fill"):
            previous_loader = b.loader()
            selector = json.dumps(required(args, "selector"))
            point = b.evaluate("""(() => {const es=Array.from(document.querySelectorAll(SELECTOR)).filter(e=>e.getClientRects().length);
              if(es.length!==1)return {error:'Selector must identify one visible element; found '+es.length};
              const e=es[0]; e.scrollIntoView({block:'center'}); const r=e.getBoundingClientRect();
              const x=r.x+r.width/2,y=r.y+r.height/2;const top=document.elementFromPoint(x,y);
              if(e.disabled||!(top===e||e.contains(top)))return {error:'Element is disabled or obscured'};
              e.focus();return {x,y};})()""".replace("SELECTOR", selector))
            if not point or "error" in point:
                page = classify_page(b.read())
                page["error"] = (point or {}).get("error", "Element unavailable")
                page["expected"] = "One visible, enabled, unobscured element. Use the current fields/selectors returned here; inspect browser read again if the page changed."
                return page
            for event in ("mousePressed", "mouseReleased"):
                b.call("Input.dispatchMouseEvent", {"type": event, "x": point["x"], "y": point["y"], "button": "left", "clickCount": 1})
            if action == "fill":
                # Send native selection and insertion so React and other app editors receive events.
                for event in ("keyDown", "keyUp"):
                    b.call("Input.dispatchKeyEvent", {"type": event, "key": "a", "code": "KeyA", "windowsVirtualKeyCode": 65, "modifiers": 2})
                b.call("Input.insertText", {"text": args.get("text", "")})
            if action == "click": b.settle(previous=previous_loader)
            else: time.sleep(0.25)
        elif action == "key":
            previous_loader = b.loader()
            key = required(args, "text")
            keys = {"Return": ("Enter", "Enter", 13), "Enter": ("Enter", "Enter", 13), "Tab": ("Tab", "Tab", 9), "Escape": ("Escape", "Escape", 27)}
            if key not in keys: raise ValueError("browser key expects Return, Tab or Escape; use computer key for other shortcuts")
            value, code, number = keys[key]
            for event in ("keyDown", "keyUp"):
                b.call("Input.dispatchKeyEvent", {"type": event, "key": value, "code": code, "windowsVirtualKeyCode": number, **({"text": "\r", "unmodifiedText": "\r"} if value == "Enter" and event == "keyDown" else {})})
            if value == "Enter": b.settle(previous=previous_loader)
            else: time.sleep(0.25)
        elif action != "read":
            raise ValueError("Unknown browser action")
        return classify_page(b.read(args.get("offset", 0)))
    finally:
        b.close()


def classify_page(page):
    """A challenge is a failed observation, never successful research evidence."""
    url = str(page.get("url", "")).lower()
    text = (str(page.get("title", "")) + " " + str(page.get("text", ""))).lower()
    phrases = ("unusual traffic from your computer network", "verify you are human",
               "checking your browser", "security verification", "complete the captcha",
               "just a moment...", "access denied", "automated queries")
    challenge_title = str(page.get("title", "")).lower()
    strong = "unusual traffic from your computer network" in text or "automated queries" in text
    if "/sorry/" in url or "captcha" in urllib.parse.urlparse(url).path or strong or "just a moment" in challenge_title or (len(text) < 2500 and any(p in text for p in phrases)):
        page["blocked"] = True
        page["error"] = "Security challenge returned instead of requested content."
        page["text"] = str(page.get("text", ""))[:900]
    return page


def search(args):
    query = required(args, "query")
    engines = [("Google", "https://www.google.com/search?q="),
               ("Bing", "https://www.bing.com/search?q="),
               ("DuckDuckGo", "https://duckduckgo.com/html/?q=")]
    attempts = []
    for name, base in engines:
        try:
            page = browser({"action": "navigate", "url": base + urllib.parse.quote(query)})
            attempts.append({"engine": name, "url": page.get("url"), "blocked": page.get("blocked", False)})
            if not page.get("blocked") and not page.get("error") and page.get("text", "").strip():
                page.update({"engine": name, "attempts": attempts,
                             "execution": "Real Chromium browser inside Shiro's local VM"})
                return page
        except Exception as error:
            attempts.append({"engine": name, "error": str(error)[:250]})
    return {"error": "Search engines returned challenges or could not load.", "blocked": True,
            "attempts": attempts, "recovery": "Navigate to known public employer careers pages, verify listings directly, or request human takeover for a required CAPTCHA. Do not treat challenge pages as job results."}


def computer(args):
    action = required(args, "action")
    if action == "screenshot":
        return screenshot()
    if action in ("click", "drag"):
        x, y = args.get("x"), args.get("y")
        if not isinstance(x, (int, float)) or not isinstance(y, (int, float)) or not 0 <= x < 1280 or not 0 <= y < 800:
            raise ValueError("Click coordinates must be inside the 1280×800 screen")
        button = args.get("button", 1)
        if button not in (1, 2, 3): raise ValueError("Invalid mouse button")
        if action == "drag":
            x2, y2 = args.get("x2", -1), args.get("y2", -1)
            if not (0 <= x2 < 1280 and 0 <= y2 < 800): raise ValueError("Drag coordinates outside desktop")
            run(["xdotool", "mousemove", str(int(x)), str(int(y)), "mousedown", "1", "mousemove", str(int(x2)), str(int(y2)), "mouseup", "1"])
        else:
            run(["xdotool", "mousemove", str(int(x)), str(int(y)), "click", str(button)])
    elif action == "type":
        text = required(args, "text")
        if len(text) > MAX_TEXT:
            raise ValueError("Text is too long")
        # Clipboard typing supports Unicode; the clipboard is entirely inside the guest.
        # Xterm uses PRIMARY for Shift+Insert; Chromium accepts CLIPBOARD.
        for selection in ("clipboard", "primary"):
            p = subprocess.Popen(["xclip", "-selection", selection], stdin=subprocess.PIPE,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            p.communicate(text.encode(), timeout=8)
        run(["xdotool", "key", "--clearmodifiers", "shift+Insert"])
    elif action == "copy":
        run(["xdotool", "key", "--clearmodifiers", "ctrl+c"])
        time.sleep(0.15)
        result = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, timeout=3)
        return {"clipboard": result.stdout[:MAX_TEXT].decode(errors="replace"), "ok": result.returncode == 0}
    elif action == "key":
        run(["xdotool", "key", "--clearmodifiers", required(args, "text")])
    elif action == "scroll":
        direction = required(args, "direction")
        if direction not in ("up", "down"):
            raise ValueError("Invalid scroll direction")
        run(["xdotool", "click", "--repeat", "4", "4" if direction == "up" else "5"])
    elif action == "launch":
        app = required(args, "text")
        if app == "browser":
            browser_tabs()
        elif app in ("terminal", "files"):
            subprocess.Popen(["xterm"] if app == "terminal" else ["thunar", str(WORKSPACE)],
                             cwd=WORKSPACE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        else:
            raise ValueError("App must be browser, terminal, or files")
    else:
        raise ValueError("Unknown computer action")
    time.sleep(0.15)
    return {"ok": True}


def shell(args):
    command = required(args, "command")
    if len(command) > 32000:
        raise ValueError("Command is too long")
    def limits():
        # Bound temporary output and files created by this process tree.
        resource.setrlimit(resource.RLIMIT_FSIZE, (64 * 1024 * 1024, 64 * 1024 * 1024))
    with tempfile.TemporaryFile() as output:
        process = subprocess.Popen(["/bin/bash", "-c", command], cwd=WORKSPACE,
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=True, preexec_fn=limits)
        timed_out = False
        try:
            process.wait(timeout=45)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        output.seek(0)
        data = output.read(MAX_TEXT + 1)
        return {"exitCode": process.returncode, "timedOut": timed_out,
                "output": data[:MAX_TEXT].decode(errors="replace"), "truncated": len(data) > MAX_TEXT}


def files(args):
    action = required(args, "action")
    if action == "mkdir":
        path = workspace_path(required(args, "path"))
        path.mkdir(parents=True, exist_ok=True)
        return {"directory": str(path.relative_to(WORKSPACE))}
    path = workspace_path(args.get("path", ""))
    if action == "list":
        if not path.is_dir():
            raise ValueError("Not a directory")
        return {"files": [{"path": str(p.relative_to(WORKSPACE.resolve())), "directory": p.is_dir(),
                           "bytes": p.stat().st_size} for p in sorted(path.iterdir())[:150] if not p.is_symlink()]}
    if action == "stat":
        return {"file": path.is_file(), "path": str(path.relative_to(WORKSPACE.resolve())), "bytes": path.stat().st_size}
    if action == "read":
        if path.stat().st_size > 1024 * 1024:
            raise ValueError("File exceeds the 1 MB text limit. Export it instead.")
        offset = args.get("offset", 0)
        if not isinstance(offset, int) or isinstance(offset, bool) or offset < 0:
            raise ValueError("offset must be a nonnegative integer; use nextOffset from the previous read")
        text = path.read_text()
        content = text[offset:offset+6000]
        return {"path": str(path.relative_to(WORKSPACE.resolve())), "content": content, "offset": offset,
                "nextOffset": offset+len(content) if offset+len(content)<len(text) else None, "totalCharacters": len(text)}
    if action == "pdf":
        from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
        from reportlab.lib.styles import getSampleStyleSheet
        from reportlab.lib import colors
        from xml.sax.saxutils import escape
        content = required(args, "content")
        if len(content) > 200000 or path.suffix.lower() != ".pdf":
            raise ValueError("PDF requires a .pdf filename and report text below 200,000 characters")
        path.parent.mkdir(parents=True, exist_ok=True)
        styles = getSampleStyleSheet(); styles['BodyText'].fontSize = 11; styles['BodyText'].leading = 16
        styles['Heading1'].textColor = colors.HexColor('#1769bd')
        blocks = []
        for section in content.split('\n\n'):
            heading = section.startswith('#')
            clean = section.lstrip('# ').strip() if heading else section.strip()
            blocks.extend([Paragraph(escape(clean).replace('\n', '<br/>'), styles['Heading1'] if heading else styles['BodyText']), Spacer(1, 12)])
        SimpleDocTemplate(str(path), leftMargin=48, rightMargin=48, topMargin=48, bottomMargin=48).build(blocks)
        return {"saved": str(path.relative_to(WORKSPACE.resolve())), "bytes": path.stat().st_size, "format": "PDF"}
    if action == "write":
        content = args.get("content")
        if not isinstance(content, str) or len(content.encode()) > 1024 * 1024:
            raise ValueError("Content must be UTF-8 text under 1 MB")
        if path == WORKSPACE.resolve():
            raise ValueError("Specify a filename")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return {"saved": str(path.relative_to(WORKSPACE.resolve())), "bytes": path.stat().st_size}
    raise ValueError("Unknown file action")


def main(payload):
    WORKSPACE.mkdir(exist_ok=True)
    tool, args = required(payload, "tool"), payload.get("arguments", {})
    if not isinstance(args, dict):
        raise ValueError("Arguments must be an object")
    if tool == "health":
        return {"ready": True, "version": "2026.10.14.4", "sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "user": os.environ.get("USER"), "workspace": str(WORKSPACE),
                "desktop": subprocess.run(["xdotool", "getdisplaygeometry"], capture_output=True).returncode == 0}
    if tool == "search":
        return search(args)
    if tool == "export":
        path = workspace_path(required(args, "path"))
        if path.stat().st_size > 32 * 1024 * 1024:
            raise ValueError("Use SSH/SCP for files larger than 32 MB")
        return {"data": base64.b64encode(path.read_bytes()).decode()}
    handlers = {"browser": browser, "computer": computer, "shell": shell, "files": files}
    if tool not in handlers:
        raise ValueError("Unknown tool")
    return handlers[tool](args)


if __name__ == "__main__":
    try:
        request = json.loads(base64.b64decode(sys.argv[1], validate=True))
        print(json.dumps(main(request), ensure_ascii=False))
    except Exception as error:
        print(json.dumps({"error": str(error)}))
