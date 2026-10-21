#!/usr/bin/env python3
"""Run browser regressions with disposable data, never the user's accounts."""
from pathlib import Path
import argparse
import importlib.util
import os
import plistlib
import shutil
import subprocess
import threading
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "notch-browser/notch-browser"
TESTS = ROOT / "notch-browser/Tests"
BUILD = ROOT / ".build/notch-browser-tests"
BUILD.mkdir(parents=True, exist_ok=True)


def run_suite(name, sources, fixtures=(), env=None, arguments=()):
    app = BUILD / (name + ".app")
    executable = app / "Contents/MacOS" / name
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources = app / "Contents/Resources"
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCES / "BrowserAgentBridge.js", resources)
    with (app / "Contents/Info.plist").open("wb") as info:
        plistlib.dump({"CFBundleIdentifier": "com.govi.notch-browser.tests." + name,
                      "CFBundleExecutable": name, "CFBundlePackageType": "APPL", "LSUIElement": True}, info)
    command = ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
               "-module-cache-path", str(BUILD / "module-cache")]
    command += [str(SOURCES / (source + ".swift")) for source in sources]
    command += [str(path) for path in fixtures]
    command += [str(TESTS / (name + ".swift")), "-o", str(executable)]
    subprocess.run(command, check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    subprocess.run([str(executable), *arguments], check=True, timeout=60, env=env)


@contextmanager
def local_fixtures():
    spec = importlib.util.spec_from_file_location("notch_transfer_fixtures", TESTS / "TransferServer.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    server = module.ThreadingHTTPServer(("127.0.0.1", 0), module.Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_port}"
    try:
        yield dict(os.environ, NOTCH_TRANSFER_TEST_URL=base, NOTCH_SESSION_TEST_URL=base + "/session-fixture")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=["all", "app-visibility", "behavior", "favicon", "favicon-unit", "favicon-metadata", "presentation", "session", "keyboard", "lookup", "lookup-layout", "license", "transfer", "foundation", "resize", "agent-bridge"], default="all")
    suite = parser.parse_args().suite
    core = ["BrowserAddressInput", "BrowserModel", "BrowserFavicon", "BrowserFaviconStore", "BrowserTabsModel", "BrowserNavigationDelegate",
            "BrowserDownloads", "BrowserAssetWebView", "BrowserAgentDOM", "BrowserAgentFrames", "BrowserPageInteraction"]
    if suite in ("all", "app-visibility"):
        run_suite("BrowserAppVisibilityTests", ["BrowserAppVisibility"])
    if suite in ("all", "agent-bridge"):
        run_suite("BrowserAgentBridgeTests", ["BrowserAgentDOM", "BrowserAgentFrames"])
    if suite in ("all", "behavior"):
        run_suite("BrowserBehaviorTests", core, [ROOT / "notch-browser/AgentTools/Tests/FixtureBrowserLibrary.swift"])
    if suite in ("all", "favicon"):
        with local_fixtures() as env:
            run_suite("BrowserFaviconTests", core,
                      [ROOT / "notch-browser/AgentTools/Tests/FixtureBrowserLibrary.swift"], env=env)
    if suite in ("all", "favicon-unit", "favicon-metadata"):
        run_suite("BrowserFaviconUnitTests", core,
                  [ROOT / "notch-browser/AgentTools/Tests/FixtureBrowserLibrary.swift"],
                  arguments=["--metadata-only"] if suite == "favicon-metadata" else [])
    if suite in ("all", "presentation"):
        with local_fixtures() as env:
            run_suite("BrowserPresentationTests", core + ["BrowserWebView", "BrowserResizeHandle"],
                      [ROOT / "notch-browser/AgentTools/Tests/FixtureBrowserLibrary.swift",
                       ROOT / "Sources/DynamicNotch/DynamicNotch.swift"], env=env)
    if suite in ("all", "session"):
        with local_fixtures() as env:
            run_suite("BrowserSessionTests", core + ["BrowserLibrary", "BrowserBackgroundColor", "BrowserSessionStore", "BrowserKeychainAccess",
                                                     "BrowserBookmarkImporter", "BrowserBackgroundImage"], env=env)
    if suite in ("all", "keyboard"):
        run_suite("BrowserKeyboardTests", core + ["BrowserAddressField"],
                  [ROOT / "notch-browser/AgentTools/Tests/FixtureBrowserLibrary.swift"])
    if suite in ("all", "lookup"):
        run_suite("BrowserLookupTests", core + ["BrowserLookup", "BrowserLookupImage", "BrowserLensHandoff", "BrowserLookupCoordinator"],
                  [ROOT / "notch-browser/AgentTools/Tests/FixtureBrowserLibrary.swift"])
    if suite in ("all", "lookup-layout"):
        run_suite("BrowserLookupLayoutTests", core + ["BrowserLookup", "BrowserLookupImage", "BrowserLensHandoff", "BrowserLookupCoordinator", "BrowserLookupBar", "BrowserGlassStyle", "BrowserWebView"],
                  [ROOT / "notch-browser/AgentTools/Tests/FixtureBrowserLibrary.swift"])
    if suite in ("all", "license"):
        run_suite("BrowserLicenseTests", ["PolarLicenseModel", "BrowserKeychainAccess"])
    if suite in ("all", "transfer"):
        with local_fixtures() as env:
            run_suite("BrowserTransferTests", ["BrowserDownloads", "BrowserAssetWebView"], env=env)
    if suite in ("all", "foundation"):
        run_suite("BookmarkImportTests", ["BrowserBookmarkImporter"])
        run_suite("BackgroundImageTests", ["BrowserBackgroundImage"])
        run_suite("KeychainInteractionTests", ["BrowserKeychainAccess"])
    if suite in ("all", "resize"):
        run_suite("CornerResizeTests", ["BrowserResizeHandle", "NotchBrowserSizing"])
