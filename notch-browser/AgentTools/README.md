# Notch Browser agent tools

The native app exposes its real WebKit tabs through a private Unix socket.
The standalone `notch-browser` CLI and bundled skill use the same sessions,
cookies, page state, and tab models as the human-facing UI. Agent access follows
the app's existing license gate.

## Start using it

Build the `notch-browser` Xcode scheme. The app includes both the native CLI and
skill, so shipping the app does not require Node, Python, or a separate daemon.
With the updated app running, install its tools once:

```sh
/absolute/path/notch-browser.app/Contents/Helpers/notch-browser setup codex
```

This installs the executable under `~/.local/share/notch-browser/agent-tools`,
links `~/.local/bin/notch-browser`, and installs the skill in
`~/.codex/skills/notch-browser` (or the configured Codex skill directory).
`setup claude` installs the Claude skill; `setup all` installs both. It does
not alter shell configuration or agent MCP settings. Keep `~/.local/bin` on
PATH and start a new agent session to discover the skill.

For development, use `notch-browser/AgentTools/bin/notch-browser` from this
checkout. It builds the standalone tool on first use and after source updates.
The binary lives under `.build/notch-browser-agent-tools`.

```sh
notch-browser status --json
notch-browser open https://example.com --session research --json
notch-browser ls --json
notch-browser action --session research --tab <tab-id> -- snapshot
notch-browser action --session research --tab <tab-id> -- fill <ref> "hello"
notch-browser action --session research --tab <tab-id> -- click <ref>
notch-browser action --session research --tab <tab-id> -- wait selector "#result"
notch-browser action --session research --tab <tab-id> -- snapshot
notch-browser action --session research done
```

`open` creates a new tab, binds the session, and reveals it. Use `--background`
to leave the visible tab and notch unchanged. Actions remain bound to their
chosen tab even when the user changes tabs. Closing that tab produces
`tab_gone`; the CLI never silently adopts a replacement. Explicit `--tab`
selects a target for automation; `--follow` also reveals it to the user.
IDs and bindings last for the current app run.

`open /absolute/path/report.html` renders an HTML artifact with access to its
parent folder for assets. `screenshot /absolute/path/capture.png` captures the
viewport. `eval <expression>` evaluates a JSON-returning expression in the
page's JavaScript world. Run `notch-browser help` for the full command surface.

## Results and recovery

Options go before `--`; page-command arguments after it are literal values.
`--json` emits one result envelope to stdout. Successful commands exit 0,
failed commands exit 1. Both include a protocol version and request ID.

```json
{"id":"request-id","protocolVersion":1,"ok":true,"data":{"tabId":"tab-id"}}
```

Errors contain a stable `error.code` and readable `error.message`.

- `stale_ref`: take a fresh snapshot, then select a new reference.
- `tab_gone`: choose an explicit existing tab or open a new one.
- `busy`: a command is running; wait for it to finish before retrying.
- `agent_paused`: the user stopped agent control; resume through the app UI.
- `license_required`: activate the app using its normal license flow.
- `timeout`: navigation/wait did not finish; the tab remains open for inspection.
- `javascript_timeout`: a page script did not respond; close an unresponsive tab.
- `result_too_large`: reduce snapshot limits or return a smaller eval result.

Snapshot references include a unique snapshot token. They expire after a new
snapshot, navigation (including back/forward cache restoration), detachment,
or a change in the target's role/name. Snapshots include a flat semantic DOM
view, readable text, truncation metadata, and known iframe limitations.
Password field values are omitted.

The notch displays an agent activity indicator with Stop/Resume. Stop blocks
new commands and interrupts pending waits/navigation; it cannot undo an action
already dispatched to a page. `action done` clears the caller's indicator
immediately. Otherwise it clears 15 seconds after the command finishes.

## Local transport

By default, the app owns `/tmp/notch-browser-<uid>/control.sock`, under an
owner-only directory (0700) with an owner-only socket (0600). It verifies the
connecting UID. A file lock prevents another app instance from stealing the
endpoint and permits crash recovery. No TCP listener is opened. Requests and
responses are newline-delimited JSON, bounded to 1 MB. The DOM bridge runs in
an isolated WebKit content world and exposes no native message handler to
websites. Page content remains untrusted data.

`NOTCH_BROWSER_SOCKET` overrides the endpoint for an app process; use the same
value or CLI `--socket` to connect. The parent directory must belong to the
current user and have permissions 0700. `--app /absolute/path/notch-browser.app`
selects the exact app to launch when no connection exists.

Commands are serialized, with a `busy` result for overlapping operations.
Named sessions provide independent tab bindings, not separate cookie profiles.

## Scope of this first version

Input uses DOM events rather than trusted hardware events. The snapshot is
not WebKit's full native accessibility tree. iframe actions, closed shadow
roots, browser permission dialogs, uploads, downloads, and CAPTCHA handling
remain human interactions. Network interception, recording, separate profiles,
and MCP registration are not included. Existing manual popup/dialog/download
behavior continues through the browser's persistent navigation delegates.

## Verification

```sh
python3 notch-browser/AgentTools/Tests/integration.py
```

The test runner compiles a separate native app from the production tab models,
controller, DOM bridge, and socket code. It replaces only licensing and session
storage with fixtures, uses an ephemeral WebKit data store, and drives the real
CLI against local pages. It checks form events and literal values, references,
background navigation, tab pinning, popups, screenshots, history, wait/eval
bounds, Stop/Resume, license enforcement, and protocol errors. It never reads
real account cookies or license keys. These checks do not establish behavior
on authenticated third-party sites.
