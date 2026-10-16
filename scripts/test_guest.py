#!/usr/bin/env python3
"""Unit tests for file boundaries. Use --vm NAME for real desktop/browser smoke tests."""
import argparse
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "Sources/Shiro/Resources/guest.py"
spec = importlib.util.spec_from_file_location("guest", SCRIPT)
guest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guest)


class RecoveryTests(unittest.TestCase):
    def test_challenge_is_an_error_not_research(self):
        page = guest.classify_page({"url": "https://www.google.com/sorry/index", "title": "Google", "text": "Unusual traffic from your computer network"})
        self.assertTrue(page["blocked"])
        self.assertIn("error", page)
        real = guest.classify_page({"url": "https://example.com/jobs", "title": "Security engineer jobs", "text": "Security verification is a skill. " * 200})
        self.assertNotIn("blocked", real)

    def test_browser_enter_has_character_event_and_waits_for_new_document(self):
        from unittest.mock import MagicMock
        b = MagicMock(); b.loader.return_value = "old-loader"
        b.read.return_value = {"url": "https://example.com/search", "text": "Results"}
        with patch.object(guest, "Browser", return_value=b):
            guest.browser({"action": "key", "text": "Return"})
        events = [c.args[1] for c in b.call.call_args_list if c.args[0] == "Input.dispatchKeyEvent"]
        self.assertEqual(events[0]["text"], "\r")
        b.settle.assert_called_once_with(previous="old-loader")

    def test_search_switches_engines_without_solving_captcha(self):
        blocked = {"url": "https://www.google.com/sorry/", "blocked": True, "error": "challenge"}
        good = {"url": "https://www.bing.com/search", "text": "Actual public careers results", "links": [{"url": "https://example.com/careers"}]}
        with patch.object(guest, "browser", side_effect=[blocked, good]) as browser:
            result = guest.search({"query": "developer jobs"})
        self.assertEqual(result["engine"], "Bing")
        self.assertEqual(browser.call_count, 2)
        self.assertTrue(result["attempts"][0]["blocked"])
        with patch.object(guest, "browser", return_value=blocked):
            failure = guest.search({"query": "jobs"})
        self.assertTrue(failure["blocked"])
        self.assertEqual(len(failure["attempts"]), 3)


class FileBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.old = guest.WORKSPACE
        guest.WORKSPACE = Path(self.temp.name) / "workspace"
        guest.WORKSPACE.mkdir()

    def tearDown(self):
        guest.WORKSPACE = self.old
        self.temp.cleanup()

    def test_pagination_preserves_full_source(self):
        text = "a" * 6000 + "important CV details"
        guest.files({"action": "write", "path": "cv.txt", "content": text})
        first = guest.files({"action": "read", "path": "cv.txt"})
        second = guest.files({"action": "read", "path": "cv.txt", "offset": first["nextOffset"]})
        self.assertEqual(first["content"] + second["content"], text)
        self.assertIsNone(second["nextOffset"])

    def test_traversal_absolute_and_symlink_are_rejected(self):
        for path in ["../secret", "/etc/passwd", "a/../../secret"]:
            with self.assertRaises(ValueError):
                guest.workspace_path(path)
        (guest.WORKSPACE / "escape").symlink_to(Path(self.temp.name))
        with self.assertRaises(ValueError):
            guest.workspace_path("escape/file")

    def test_files_and_export_round_trip(self):
        guest.files({"action": "write", "path": "report/notes.md", "content": "Shiro 日本語"})
        result = guest.files({"action": "read", "path": "report/notes.md"})
        self.assertEqual(result["content"], "Shiro 日本語")
        result = guest.main({"tool": "export", "arguments": {"path": "report/notes.md"}})
        self.assertEqual(base64.b64decode(result["data"]).decode(), "Shiro 日本語")
        inside = str(guest.WORKSPACE / "report/notes.md")
        self.assertEqual(guest.files({"action": "read", "path": inside})["content"], "Shiro 日本語")

    def test_read_back_verification_and_tamper_detection(self):
        guest.files({"action": "write", "path": "cv.md", "content": "Actual CV 日本語"})
        first = guest.files({"action": "verify", "path": "cv.md"})
        self.assertEqual(first["text"], "Actual CV 日本語")
        self.assertEqual(len(first["sha256"]), 64)
        guest.files({"action": "write", "path": "cv.md", "content": "Changed"})
        self.assertNotEqual(guest.files({"action": "verify", "path": "cv.md"})["sha256"], first["sha256"])
        guest.files({"action": "write", "path": "bad.pdf", "content": "Not a PDF"})
        with self.assertRaises(ValueError):
            guest.files({"action": "verify", "path": "bad.pdf"})
        guest.files({"action": "write", "path": "empty.md", "content": " "})
        with self.assertRaises(ValueError):
            guest.files({"action": "verify", "path": "empty.md"})
        with self.assertRaises(ValueError):
            guest.files({"action": "verify", "path": "../secret"})

    def test_pdf_reads_use_extracted_text(self):
        path = guest.WORKSPACE / "cv.pdf"
        path.write_bytes(b"%PDF- binary\x93")
        with patch.object(guest.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=b"Readable candidate facts", stderr=b"")):
            self.assertEqual(guest.files({"action": "read", "path": "cv.pdf"})["content"], "Readable candidate facts")
            self.assertEqual(guest.files({"action": "verify", "path": "cv.pdf"})["text"], "Readable candidate facts")

    def test_docx_read_back(self):
        import zipfile
        path = guest.WORKSPACE / "cv.docx"
        with zipfile.ZipFile(path, "w") as doc:
            doc.writestr("word/document.xml", '<w:document xmlns:w="word"><w:t>Candidate facts</w:t></w:document>')
        self.assertEqual(guest.files({"action": "verify", "path": "cv.docx"})["text"], "Candidate facts")

    def test_file_metadata_and_direct_input(self):
        guest.files({"action": "write", "path": "output.pdf", "content": "pdf test"})
        self.assertTrue(guest.files({"action": "stat", "path": "output.pdf"})["file"])
        with patch.object(guest, "run") as run:
            guest.computer({"action": "drag", "x": 20, "y": 30, "x2": 90, "y2": 100})
            self.assertIn("mousedown", run.call_args[0][0])
        with self.assertRaises(ValueError):
            guest.computer({"action": "drag", "x": 20, "y": 30, "x2": 1280, "y2": 100})

    def test_unknown_tools_and_bad_coordinates_are_rejected(self):
        with self.assertRaises(ValueError):
            guest.main({"tool": "host_shell", "arguments": {}})
        with self.assertRaises(ValueError):
            guest.computer({"action": "click", "x": -1, "y": 12})


def smoke(vm):
    def call(tool, args):
        payload = base64.b64encode(json.dumps({"tool": tool, "arguments": args}).encode()).decode()
        completed = subprocess.run(["limactl", "shell", vm, "--", "sudo", "-u", "shiro-local", "env",
                                    "HOME=/home/shiro-local", "DISPLAY=:88", "XAUTHORITY=/home/shiro-local/.Xauthority",
                                    "python3", "/opt/shiro-local/guest.py", payload], capture_output=True, text=True, timeout=65, check=True)
        result = json.loads(completed.stdout)
        if "error" in result:
            raise RuntimeError(result["error"])
        return result

    health = call("health", {})
    assert health["desktop"] is True, health
    shell = call("shell", {"command": "whoami; uname -m; test ! -e /Users"})
    assert shell["exitCode"] == 0 and "shiro-local" in shell["output"], shell
    text = "# Shiro verification\n\nLocal VM tools work.\n"
    call("files", {"action": "write", "path": "shiro-verification.md", "content": text})
    assert call("files", {"action": "read", "path": "shiro-verification.md"})["content"] == text
    assert base64.b64decode(call("export", {"path": "shiro-verification.md"})["data"]).decode() == text
    page = call("browser", {"action": "navigate", "url": "https://example.com"})
    assert page["title"] == "Example Domain" and page["url"].startswith("https://example.com"), page
    screenshot = call("computer", {"action": "screenshot"})
    assert base64.b64decode(screenshot["image"]).startswith(b"\x89PNG"), "Invalid screenshot"
    (ROOT / "docs/vm-verification.png").write_bytes(base64.b64decode(screenshot["image"]))
    print("PASS: VM identity, host isolation, shell, file write/read/export, Chromium navigation/read, desktop screenshot")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--vm")
    args = parser.parse_args()
    if args.vm:
        smoke(args.vm)
    else:
        unittest.main(argv=[__file__])
