#!/usr/bin/env python3
"""Exercise the shipped CLI against production controllers in real WKWebViews.

Only session persistence/licensing dependencies are substituted. Test pages,
cookie storage, preferences, socket, and output files are isolated.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import tempfile
import time

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parents[1]
APP_SOURCES = TOOLS.parent / "notch-browser"
BUILD = REPO / ".build/notch-browser-agent-tests"
BUILD.mkdir(parents=True, exist_ok=True)
CLI = REPO / ".build/notch-browser-agent-tools/notch-browser"


def compile_tools():
    subprocess.run([str(TOOLS / "build.sh")], check=True, stdout=subprocess.DEVNULL)
    app = BUILD / "AgentHarness.app"
    resources = app / "Contents/Resources"
    executable = app / "Contents/MacOS/AgentHarness"
    resources.mkdir(parents=True, exist_ok=True)
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(APP_SOURCES / "BrowserAgentBridge.js", resources)
    (app / "Contents/Info.plist").write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.govi.notch-browser.agent-tests</string><key>CFBundleExecutable</key><string>AgentHarness</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>''')
    sources = ["BrowserAddressInput", "BrowserModel", "BrowserTabsModel", "BrowserNavigationDelegate", "BrowserDownloads", "BrowserAssetWebView", "BrowserAgentActivity", "BrowserAgentDOM", "BrowserAgentController", "BrowserAgentSocket", "BrowserAgentServer"]
    command = ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(BUILD / "module-cache"),
               str(TOOLS / "Tests/FixtureBrowserLibrary.swift"), str(TOOLS / "Tests/Harness.swift")]
    command += [str(APP_SOURCES / (name + ".swift")) for name in sources]
    command += ["-o", str(executable)]
    subprocess.run(command, check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return executable


def main():
    executable = compile_tools()
    checks = []
    with tempfile.TemporaryDirectory(prefix="nb-agent-test-") as temp:
        root = Path(temp)
        endpoint = root / "socket/control.sock"
        fixture = root / "fixture.html"
        shutil.copy2(TOOLS / "Tests/fixture.html", fixture)
        shutil.copy2(TOOLS / "Tests/popup.html", root / "popup.html")
        env = os.environ.copy()
        env["NOTCH_BROWSER_TEST_DIR"] = str(root)
        env["NOTCH_BROWSER_SOCKET"] = str(endpoint)
        log = open(root / "harness.log", "w")
        process = subprocess.Popen([str(executable)], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 15
            while not (root / "ready.json").exists():
                if process.poll() is not None:
                    log.flush()
                    raise AssertionError((root / "harness.log").read_text())
                assert time.monotonic() < deadline, "Native harness startup timed out"
                time.sleep(0.1)
            assert json.loads((root / "ready.json").read_text())["ready"]
            assert stat.S_IMODE(endpoint.parent.stat().st_mode) == 0o700
            assert stat.S_IMODE(endpoint.stat().st_mode) == 0o600
            checks.append("private socket and native app startup")

            def run(*args, error=None, session="flow", timeout=10000):
                command = [str(CLI), "--json", "--session", session, "--timeout", str(timeout)] + list(args)
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=40)
                try:
                    envelope = json.loads(result.stdout)
                except Exception:
                    raise AssertionError(f"CLI did not return JSON: {result.stdout!r} {result.stderr!r}")
                if error:
                    assert result.returncode == 1 and not envelope["ok"], envelope
                    assert envelope["error"]["code"] == error, envelope
                    return envelope
                assert result.returncode == 0 and envelope["ok"], envelope
                return envelope["data"]

            def action(tab, name, *args, **kwargs):
                return run("action", "--tab", tab, "--", name, *args, **kwargs)

            def ref(snapshot, name):
                return next(element["ref"] for element in snapshot["elements"] if element["name"] == name)

            def control(command):
                (root / "control.txt").write_text(command)
                deadline = time.monotonic() + 3
                while (root / "control.txt").exists():
                    assert time.monotonic() < deadline
                    time.sleep(0.03)

            assert run("status")["engine"] == "WebKit"
            tab = run("open", str(fixture), "--background")["id"]
            snap = action(tab, "snapshot")
            assert snap["title"] == "Agent integration fixture", snap
            assert snap["frameCount"] == 1 and snap["limitations"]
            assert "fixture-password-must-not-leak" not in json.dumps(snap)
            assert not any(e["name"] == "Hidden action" for e in snap["elements"])
            assert any(e["name"] == "Shadow action" for e in snap["elements"])
            checks.append("background navigation, semantic snapshot, shadow DOM, password redaction")

            run("action", "--", "fill", error="invalid_argument")
            action(tab, "fill", ref(snap, "Read only"), "changed", error="element_read_only")
            action(tab, "click", ref(snap, "Disabled action"), error="element_disabled")
            value = 'Ada "quoted"; window.__unexpected = true; ✓'
            action(tab, "fill", ref(snap, "Your name"), value)
            notes = 'Multiline notes\n"quoted" ✓'
            action(tab, "fill", ref(snap, "Your notes"), notes)
            assert action(tab, "eval", "document.getElementById('notes').value")["result"] == notes
            action(tab, "select", ref(snap, "Plan"), "Pro")
            action(tab, "check", ref(snap, "Remember my choice"))
            state = action(tab, "eval", "({name:document.getElementById('name').value,plan:document.getElementById('plan').value,checked:document.getElementById('consent').checked,events:window.events,unexpected:!!window.__unexpected})")["result"]
            assert state["name"] == value and state["plan"] == "pro" and state["checked"], state
            assert [e[0] for e in state["events"]] == ["input", "change"]
            assert not state["unexpected"]
            action(tab, "press", ref(snap, "Your name"), "Enter")
            action(tab, "wait", "selector", "#saved")
            assert "Saved:" in action(tab, "text")["text"]
            checks.append("fill/select/check, real page events, literal argument escaping, Enter submission, verification")

            old = ref(snap, "Your name")
            snap = action(tab, "snapshot")
            action(tab, "fill", old, "outdated", error="stale_ref")
            removed = ref(snap, "Replace action")
            action(tab, "click", removed)
            action(tab, "click", removed, error="stale_ref")
            renamed = ref(snap, "Original label")
            action(tab, "eval", "(document.getElementById('rename').textContent='Changed label',true)")
            action(tab, "click", renamed, error="stale_ref")
            checks.append("stale references after snapshot, node replacement, and semantic changes")

            snap = action(tab, "snapshot")
            action(tab, "click", ref(snap, "Shadow action"))
            assert action(tab, "eval", "document.getElementById('result').textContent")["result"] == "Shadow clicked"
            action(tab, "scroll", "down", "700")
            assert action(tab, "eval", "window.scrollY")["result"] > 0
            action(tab, "scroll", "up", "10000")
            run("tab", tab)
            run("expand")
            screenshot = root / "viewport.png"
            action(tab, "screenshot", str(screenshot))
            assert screenshot.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
            assert screenshot.stat().st_size > 1000
            shutil.copy2(screenshot, BUILD / "viewport.png")
            run("collapse")
            assert action(tab, "eval", "document.getElementById('name').value")["result"] == value
            background_image = root / "background.png"
            action(tab, "screenshot", str(background_image))
            assert background_image.stat().st_size > 1000
            shutil.copy2(background_image, BUILD / "background.png")
            checks.append("shadow-root interaction, scrolling, screenshots, state retained after collapse")

            # A user switching tabs cannot redirect a session's implicit target.
            other = run("open", str(root / "popup.html"), session="other")["id"]
            assert run("action", "--", "eval", "document.title")["result"] == "Agent integration fixture"
            assert run("ls")["tabs"][-1]["id"] == other
            action(other, "close", session="other")
            run("action", "--", "snapshot", session="other", error="tab_gone")
            checks.append("session pinning across tab switching, explicit targets, closed-tab errors")

            # Popup delegates must belong to the popup model, not the opener.
            run("tab", tab)
            snap = action(tab, "snapshot")
            action(tab, "click", ref(snap, "Open popup"))
            deadline = time.monotonic() + 5
            popup = None
            while time.monotonic() < deadline:
                listing = run("ls")["tabs"]
                popup = next((t for t in listing if t["id"] != tab and t["url"].endswith("/popup.html")), None)
                if popup: break
                time.sleep(0.1)
            assert popup, listing
            popup_snap = run("action", "--tab", popup["id"], "--follow", "--", "snapshot", session="popup")
            assert popup_snap["title"] == "Popup fixture", popup_snap
            action(popup["id"], "click", ref(popup_snap, "Popup action"), session="popup")
            assert action(popup["id"], "text", session="popup")["text"].endswith("Popup clicked")
            assert action(tab, "eval", "document.title")["result"] == "Agent integration fixture"
            checks.append("popup routing and independent delegate ownership")

            action(tab, "eval", "(setTimeout(()=>{const x=document.createElement('button');x.id='delayed';x.textContent='Delayed';document.body.append(x)},150),true)")
            action(tab, "wait", "selector", "#delayed")
            action(tab, "wait", "selector", "#never-exists", timeout=200, error="timeout")
            action(tab, "wait", "selector", "[[invalid", error="invalid_selector")
            action(tab, "eval", "new Promise(()=>{})", timeout=200, error="javascript_timeout")
            assert action(tab, "eval", "1+1")["result"] == 2
            checks.append("dynamic waits, invalid selectors, bounded wait/eval timeouts and recovery")

            before_navigation = action(tab, "snapshot")
            action(tab, "navigate", str(root / "popup.html"))
            action(tab, "click", ref(before_navigation, "Your name"), error="stale_ref")
            action(tab, "back")
            assert action(tab, "eval", "document.title")["result"] == "Agent integration fixture"
            action(tab, "fill", ref(before_navigation, "Your name"), "cached", error="stale_ref")
            action(tab, "forward")
            assert action(tab, "eval", "document.title")["result"] == "Popup fixture"
            action(tab, "reload")
            checks.append("navigation/history, reload, and stale refs across documents")

            pending = subprocess.Popen([str(CLI), "--json", "--session", "flow", "action", "--tab", tab, "--timeout", "5000", "--", "wait", "selector", "#never-exists"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            deadline = time.monotonic() + 3
            while not run("status")["busy"]:
                assert time.monotonic() < deadline
                time.sleep(0.03)
            action(tab, "snapshot", session="blocked", error="busy")
            control("pause")
            stdout, stderr = pending.communicate(timeout=3)
            assert pending.returncode == 1 and json.loads(stdout)["error"]["code"] == "agent_paused", (stdout, stderr)
            action(tab, "snapshot", error="agent_paused")
            assert run("status")["paused"]
            control("resume")
            action(tab, "snapshot")
            assert run("status")["activeSession"] == "flow"
            run("action", "done")
            assert run("status")["activeSession"] is None
            checks.append("busy isolation, Stop aborting waits, paused commands, Resume and done")

            control("locked")
            assert not run("status")["unlocked"]
            run("ls", error="license_required")
            action(tab, "eval", "1+1", error="license_required")
            run("open", str(fixture), error="license_required")
            control("unlocked")
            checks.append("license gate on discovery, reads, actions, and navigation")

            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.connect(str(endpoint))
                client.sendall(b'{"id":"bad-version","protocolVersion":99,"command":"ls","args":[]}\n')
                raw = client.makefile("rb").readline()
                assert json.loads(raw)["error"]["code"] == "protocol_mismatch"
            missing = subprocess.run([str(CLI), "--json", "--socket", str(root / "missing.sock"), "status"], capture_output=True, text=True)
            assert missing.returncode == 1 and json.loads(missing.stdout)["error"]["code"] == "app_not_running"
            checks.append("protocol rejection, structured errors, and CLI exit status")

            # Closing the last tab leaves a functional empty fallback.
            for t in run("ls")["tabs"]:
                action(t["id"], "close")
            remaining = run("ls")["tabs"]
            assert len(remaining) == 1 and remaining[0]["empty"]
            checks.append("last-tab fallback")
        finally:
            if process.poll() is None:
                (root / "control.txt").write_text("shutdown")
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.terminate(); process.wait(timeout=5)
            log.close()
    print(f"PASS: {len(checks)} native integration scenarios")
    for check in checks: print(f"  {check}")


if __name__ == "__main__": main()
