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
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parents[1]
APP_SOURCES = TOOLS.parent / "notch-browser"
BUILD = REPO / ".build/notch-browser-agent-tests"
BUILD.mkdir(parents=True, exist_ok=True)
CLI = REPO / ".build/notch-browser-agent-tools/notch-browser"


class FixtureHTTPHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


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
    sources = ["BrowserAddressInput", "BrowserModel", "BrowserTabsModel", "BrowserNavigationDelegate", "BrowserDownloads", "BrowserAssetWebView", "BrowserAgentActivity", "BrowserAgentDOM", "BrowserAgentFrames", "BrowserPageInteraction", "BrowserAgentController", "BrowserAgentSocket", "BrowserAgentServer"]
    command = ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(BUILD / "module-cache"),
               str(TOOLS / "Tests/FixtureBrowserLibrary.swift"), str(TOOLS / "Tests/MediaFixture.swift"), str(TOOLS / "Tests/Harness.swift")]
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
        shutil.copy2(TOOLS / "Tests/extraction.html", root / "extraction.html")
        for name in ("frame-child.html", "frame-nested.html", "interactions.html", "verification.html"):
            shutil.copy2(TOOLS / "Tests" / name, root / name)
        upload_file = root / 'reference "one" ✓.txt'
        upload_file.write_text("Synthetic upload content — no user data.")
        upload_second = root / "reference-two.txt"
        upload_second.write_text("Second synthetic file.")
        (root / "poster.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#2864dc"/></svg>')
        http = ThreadingHTTPServer(("127.0.0.1", 0), partial(FixtureHTTPHandler, directory=str(root)))
        http_thread = threading.Thread(target=http.serve_forever, daemon=True)
        http_thread.start()
        remote_frame = f"http://127.0.0.1:{http.server_port}/frame-child.html"
        (root / "frames.html").write_text(f'<!doctype html><html><head><title>Frame host</title></head><body><h1>Main frame</h1><iframe id="embedded" title="Cross-origin form" width="700" height="500" src="{remote_frame}"></iframe></body></html>')
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

            status = run("status")
            assert status["engine"] == "WebKit" and {"extract", "media-frame"}.issubset(status["capabilities"])
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
            # Keep the promise reachable. WebKit may otherwise garbage-collect
            # it and report an unreachable result before our timeout expires.
            action(tab, "eval", "(window.__pendingAgentPromise=new Promise(()=>{}))", timeout=200, error="javascript_timeout")
            action(tab, "eval", "(window.__pendingAgentPromise=null,true)")
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

            frame_tab = run("open", str(root / "frames.html"), "--background", session="frames")["id"]
            listing = action(frame_tab, "frames", session="frames")["frames"]
            child = next(item["id"] for item in listing if item["title"] == "Cross-origin child")
            nested = next(item["id"] for item in listing if item["title"] == "Nested child")

            def in_frame(frame_id, name, *args, **kwargs):
                return run("action", "--tab", frame_tab, "--frame", frame_id, "--", name, *args, session="frames", **kwargs)

            # The ordinary page world cannot cross this origin boundary.
            assert action(frame_tab, "eval", "document.getElementById('embedded').contentDocument===null", session="frames")["result"]
            child_snap = in_frame(child, "snapshot")
            embedded_name = ref(child_snap, "Embedded name")
            in_frame(child, "fill", embedded_name, "Ada")
            in_frame(child, "click", ref(child_snap, "Save embedded"))
            assert "Saved Ada" in in_frame(child, "text")["text"]
            action(frame_tab, "fill", embedded_name, "wrong frame", session="frames", error="stale_ref")
            in_frame(child, "wait", "selector", "#result")
            in_frame(child, "wait", "url", "frame-child.html")
            in_frame(child, "eval", "document.getElementById('embedded-name').value")
            action(frame_tab, "frames", session="frames")
            in_frame(child, "fill", embedded_name, "Grace")
            in_frame(child, "upload", ref(child_snap, "Embedded file"), str(upload_file))
            assert in_frame(child, "eval", "window.embeddedFiles")["result"] == [upload_file.name]
            in_frame(child, "eval", "(window.frameConfirm=confirm('Embedded confirmation'))", error="dialog_pending")
            embedded_dialog = action(frame_tab, "dialogs", session="frames")["dialogs"][0]
            assert "127.0.0.1" in embedded_dialog["origin"]
            action(frame_tab, "dialog", embedded_dialog["id"], "accept", session="frames")
            assert in_frame(child, "eval", "window.frameConfirm")["result"] is True
            nested_snap = in_frame(nested, "snapshot")
            in_frame(nested, "fill", ref(nested_snap, "Nested note"), "Nested works")
            in_frame(nested, "click", ref(nested_snap, "Save nested"))
            assert "Nested works" in in_frame(nested, "extract")["text"]
            in_frame(child, "screenshot", str(root / "frame.png"), error="unsupported_in_frame")
            action(frame_tab, "eval", "(document.getElementById('embedded').src+='?next',true)", session="frames")
            in_frame(child, "snapshot", error="frame_gone")
            action(frame_tab, "wait", "ready", session="frames")
            fresh = action(frame_tab, "frames", session="frames")["frames"]
            new_child = next(item["id"] for item in fresh if item["title"] == "Cross-origin child")
            assert new_child != child
            action(frame_tab, "eval", "(document.getElementById('embedded').remove(),true)", session="frames")
            in_frame(new_child, "snapshot", error="frame_gone")
            run("close", "--tab", frame_tab, session="frames")
            checks.append("cross-origin and nested frame discovery/actions, scoped refs, waits, extraction, navigation/removal expiry")

            interaction_tab = run("open", str(root / "interactions.html"), "--background", session="interactions")["id"]
            interaction_snap = action(interaction_tab, "snapshot", session="interactions")
            single = ref(interaction_snap, "Single file")
            multiple = ref(interaction_snap, "Multiple files")
            assert next(item for item in interaction_snap["elements"] if item["ref"] == single)["role"] == "file-upload"
            selected = action(interaction_tab, "upload", single, str(upload_file), session="interactions")
            assert selected["files"] == [upload_file.name] and selected["inputMode"] == "native-file-picker"
            events = action(interaction_tab, "eval", "window.fileEvents", session="interactions")["result"]
            assert events[-1]["trusted"] and events[-1]["files"][0]["text"] == upload_file.read_text(), events
            action(interaction_tab, "upload", multiple, str(upload_file), str(upload_second), session="interactions")
            names = action(interaction_tab, "eval", "Array.from(document.getElementById('multiple').files).map(x=>x.name)", session="interactions")["result"]
            assert names == [upload_file.name, upload_second.name]
            action(interaction_tab, "upload", single, str(upload_file), str(upload_second), session="interactions", error="invalid_argument")
            action(interaction_tab, "upload", single, str(root), session="interactions", error="invalid_file")
            action(interaction_tab, "upload", single, str(root / "missing.txt"), session="interactions", error="invalid_file")
            action(interaction_tab, "upload", single, "https://example.org/file.txt", session="interactions", error="invalid_file")
            action(interaction_tab, "upload", ref(interaction_snap, "Confirm fixture"), str(upload_file), session="interactions", error="wrong_element_type")
            assert action(interaction_tab, "dialogs", session="interactions")["dialogs"] == []
            checks.append("native single/multiple file inputs, trusted change events and file bytes, path validation, cross-origin uploads")

            # A custom upload button can open a hidden input. Retain the pending
            # promise until file selection so this exercises dialog interruption.
            action(interaction_tab, "eval", "(window.filePromise=new Promise(resolve=>{document.getElementById('hidden-file').addEventListener('change',()=>resolve(true),{once:true});document.getElementById('custom-upload').click()}))", session="interactions", error="dialog_pending")
            picker = action(interaction_tab, "dialogs", session="interactions")["dialogs"][0]
            assert action(interaction_tab, "wait", "dialog", session="interactions")["dialogs"][0]["id"] == picker["id"]
            assert picker["kind"] == "file-picker" and picker["canRespondViaCLI"]
            action(interaction_tab, "choose-files", picker["id"], str(upload_file), str(upload_second), session="interactions", error="invalid_argument")
            action(interaction_tab, "choose-files", picker["id"], str(upload_second), session="interactions")
            assert action(interaction_tab, "eval", "document.getElementById('hidden-file').files[0].name", session="interactions")["result"] == upload_second.name
            action(interaction_tab, "wait", "dialog", session="interactions", timeout=100, error="timeout")
            action(interaction_tab, "dialog", picker["id"], "dismiss", session="interactions", error="dialog_gone")
            checks.append("pending custom/hidden file-picker inspection, explicit file selection, multiplicity and stale-dialog checks")

            for kind, button, answer, expected in [("confirm", "Confirm fixture", "accept", True), ("confirm", "Confirm fixture", "dismiss", False),
                                                     ("prompt", "Prompt fixture", "accept", 'Literal "text" ✓\nnext line'), ("prompt", "Prompt fixture", "dismiss", None),
                                                     ("alert", "Alert fixture", "accept", True)]:
                action(interaction_tab, "click", ref(interaction_snap, button), session="interactions", error="dialog_pending")
                dialog = action(interaction_tab, "dialogs", session="interactions")["dialogs"][0]
                assert dialog["kind"] == kind
                response = [dialog["id"], answer] + ([expected] if kind == "prompt" and answer == "accept" else [])
                action(interaction_tab, "dialog", *response, session="interactions")
                key = {"confirm": "confirmResult", "prompt": "promptResult", "alert": "alertReturned"}[kind]
                assert action(interaction_tab, "eval", "window." + key, session="interactions")["result"] == expected
            run("tab", interaction_tab, session="interactions")
            control("permission")
            permission = action(interaction_tab, "dialogs", session="interactions")["dialogs"][0]
            assert permission["requiresUser"] and not permission["canRespondViaCLI"]
            action(interaction_tab, "dialog", permission["id"], "accept", session="interactions", error="human_required")
            action(interaction_tab, "dialog", permission["id"], "dismiss", session="interactions", error="human_required")
            assert action(interaction_tab, "blockers", session="interactions")["dialogs"][0]["kind"] == "permission"
            handoff = action(interaction_tab, "handoff", session="interactions")
            assert handoff["paused"] and run("status")["paused"]
            action(interaction_tab, "snapshot", session="interactions", error="agent_paused")
            control("permission-clear")
            assert (root / "permission-result.txt").read_text() == "denied"
            control("resume")
            action(interaction_tab, "snapshot", session="interactions")
            run("close", "--tab", interaction_tab, session="interactions")
            checks.append("alert/confirm/prompt responses, permission grants reserved for user, visible handoff, pause/resume and cleanup")

            verify_tab = run("open", str(root / "verification.html"), "--background", session="verify")["id"]
            verify_snap = action(verify_tab, "snapshot", session="verify")
            assert "fixture-token-must-not-leak" not in json.dumps(verify_snap)
            blockers = action(verify_tab, "blockers", session="verify")
            assert blockers["challengeDocument"] and blockers["blockers"][0]["requiresUser"]
            action(verify_tab, "click", ref(verify_snap, "Verification fixture control"), session="verify", error="human_required")
            action(verify_tab, "eval", "document.title", session="verify", error="human_required")
            assert action(verify_tab, "handoff", session="verify")["paused"]
            control("resume")
            run("close", "--tab", verify_tab, session="verify")
            checks.append("local verification-marker detection, token redaction, blocked automated challenge actions and user handoff")

            extraction_tab = run("open", str(root / "extraction.html"), "--background", session="extract")["id"]
            run("tab", extraction_tab, session="extract")
            run("expand", session="extract")
            try:
                action(extraction_tab, "wait", "selector", "#media-ready", session="extract")
            except AssertionError:
                print("Media readiness:", action(extraction_tab, "eval", "({state:clip.readyState,network:clip.networkState,error:clip.error?.message,source:clip.currentSrc,tracks:clip.textTracks.length,marker:!!document.getElementById('media-ready')})", session="extract"))
                raise
            before = action(extraction_tab, "eval", "({paused:clip.paused,time:clip.currentTime,mode:captions.mode,scroll:scrollY})", session="extract")["result"]
            extracted = action(extraction_tab, "extract", session="extract")
            assert extracted["schemaVersion"] == 1 and extracted["scope"] == "article", extracted
            assert extracted["canonicalURL"] == "https://example.org/reel/reference"
            assert extracted["metadata"]["author"] == "Fixture Creator"
            assert "Opening wide shot" in extracted["text"] and "Unrelated feed entry" not in extracted["text"]
            for secret in ["hidden-content-must-not-leak", "extraction-password-must-not-leak", "draft-value-must-not-leak", "frame-text-must-not-leak"]:
                assert secret not in json.dumps(extracted), secret
            assert extracted["links"] == [{"text": "Original reference", "url": "https://example.org/source"}]
            assert extracted["images"][0]["alt"] == "Blue product reference"
            assert extracted["structuredData"][0]["author"] == "Fixture Creator"
            assert extracted["structuredData"][1]["contentURL"] is None
            assert extracted["transcripts"][0]["text"] == "Publisher supplied transcript."
            video = next(item for item in extracted["media"] if item["kind"] == "video")
            audio = next(item for item in extracted["media"] if item["kind"] == "audio")
            assert video["tracks"][0]["cues"][0]["text"] == "Start with a wide shot."
            assert extracted["transcriptAvailable"] and any("embedded frame" in x for x in extracted["limitations"])
            assert any("could not be parsed" in x for x in extracted["limitations"])
            (BUILD / "extraction.json").write_text(json.dumps(extracted, indent=2))
            plain = subprocess.run([str(CLI), "--session", "extract", "--tab", extraction_tab, "extract"],
                                   env=env, capture_output=True, text=True, timeout=15)
            assert plain.returncode == 0 and json.loads(plain.stdout)["schemaVersion"] == 1, plain.stdout
            checks.append("structured extraction, scoped readable text, metadata, images, captions, and credential exclusion")

            action(extraction_tab, "extract", "[", session="extract", error="invalid_selector")
            action(extraction_tab, "extract", "#missing", session="extract", error="element_not_found")
            scoped = action(extraction_tab, "extract", "#other", session="extract")
            assert "Unrelated feed entry" in scoped["text"] and not scoped["media"]
            action(extraction_tab, "media-frame", video["ref"], str(root / "stale.png"), session="extract", error="stale_ref")
            limited = run("action", "--tab", extraction_tab, "--max-chars", "20", "--limit", "1", "--", "extract", session="extract")
            assert limited["truncated"] and len(limited["text"]) <= 20 and len(limited["media"]) <= 1
            checks.append("extraction selector errors, scope isolation, collection/text budgets, and media reference expiry")

            extracted = action(extraction_tab, "extract", session="extract")
            video = next(item for item in extracted["media"] if item["kind"] == "video")
            audio = next(item for item in extracted["media"] if item["kind"] == "audio")
            action(extraction_tab, "snapshot", session="extract")
            frame = root / "frame.png"
            captured = action(extraction_tab, "media-frame", video["ref"], str(frame), session="extract")
            assert captured["width"] == captured["height"] == 64 and "png" not in captured
            assert frame.read_bytes().startswith(b"\x89PNG\r\n\x1a\n") and frame.stat().st_size > 100
            shutil.copy2(frame, BUILD / "frame.png")
            after = action(extraction_tab, "eval", "({paused:clip.paused,time:clip.currentTime,mode:captions.mode,scroll:scrollY})", session="extract")["result"]
            assert before == after, (before, after)
            action(extraction_tab, "media-frame", audio["ref"], str(root / "audio.png"), session="extract", error="wrong_element_type")
            action(extraction_tab, "media-frame", video["ref"], "relative.png", session="extract", error="invalid_argument")
            remote = f"http://127.0.0.1:{http.server_port}/reference.mp4"
            action(extraction_tab, "eval", f"(clip.addEventListener('loadeddata',()=>{{const m=document.createElement('span');m.id='cross-origin-ready';m.textContent='Remote media ready';document.body.append(m)}},{{once:true}}),clip.src={json.dumps(remote)},clip.load(),true)", session="extract")
            action(extraction_tab, "wait", "selector", "#cross-origin-ready", session="extract")
            cross_origin = action(extraction_tab, "extract", session="extract")
            remote_video = next(item for item in cross_origin["media"] if item["kind"] == "video")
            action(extraction_tab, "media-frame", remote_video["ref"], str(root / "denied.png"), session="extract", error="frame_access_denied")
            assert not (root / "denied.png").exists()
            action(extraction_tab, "eval", "(clip.removeAttribute('src'),clip.load(),true)", session="extract")
            action(extraction_tab, "media-frame", remote_video["ref"], str(root / "changed.png"), session="extract", error="stale_ref")
            action(extraction_tab, "eval", "(document.querySelectorAll('script[type=\"application/ld+json\"]').forEach(x=>x.remove()),document.getElementById('clip').outerHTML='<video width=64 height=64 controls></video>',true)", session="extract")
            missing = action(extraction_tab, "extract", session="extract")
            assert not missing["transcriptAvailable"] and any("No loaded captions" in x for x in missing["limitations"])
            missing_video = next(item for item in missing["media"] if item["kind"] == "video")
            action(extraction_tab, "media-frame", missing_video["ref"], str(root / "empty.png"), session="extract", error="frame_unavailable")
            run("close", "--tab", extraction_tab, session="extract")
            checks.append("real decoded video frame, playback/scroll preservation, cross-origin protection, and unavailable media reporting")

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
            action(tab, "extract", error="agent_paused")
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
            action(tab, "extract", error="license_required")
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
            http.shutdown()
            http.server_close()
            http_thread.join(timeout=2)
    print(f"PASS: {len(checks)} native integration scenarios")
    for check in checks: print(f"  {check}")


if __name__ == "__main__": main()
