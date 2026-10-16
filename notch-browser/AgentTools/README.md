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

## Frames, files, dialogs and user handoff

`frames` discovers main, cross-origin and nested frames through WebKit's public
frame API. Use a returned ID with `--frame` on snapshots, text/extraction,
element actions, media capture, eval and waits. References belong to the frame
that produced them. A removed/navigated frame returns `frame_gone`; run `frames`
again and take a fresh snapshot. The default target is always the main frame.
Tab navigation/closing, native dialog controls and viewport screenshots are
tab-level commands; omit `--frame` for them.

```sh
notch-browser action --tab <tab-id> --json -- frames
notch-browser action --tab <tab-id> --frame <frame-id> --json -- snapshot
notch-browser action --tab <tab-id> --frame <frame-id> -- fill <ref> "hello"
notch-browser action --tab <tab-id> --frame <frame-id> -- upload <file-input-ref> /absolute/path/reference.png
```

`upload` supplies explicit local files through WebKit's native chooser, including
inside frames. It supports single and multiple inputs, validates readable
regular files, and never uploads a directory or recursively finds files. The
limit is 100 explicit paths. A successful response reports native file selection;
inspect the website to verify its subsequent processing/server upload.

For custom buttons that open hidden file inputs, click the button and inspect
`dialogs`. A blocked JavaScript command returns `dialog_pending` promptly while
preserving the dialog. `wait dialog` handles pickers that open asynchronously.
Use `choose-files` with the current dialog ID, or dismiss it with `dialog`.

```sh
notch-browser action --tab <tab-id> --json -- dialogs
notch-browser action --tab <tab-id> -- wait dialog
notch-browser action --tab <tab-id> -- choose-files <dialog-id> /absolute/path/reference.png
notch-browser action --tab <tab-id> -- dialog <dialog-id> accept
notch-browser action --tab <tab-id> -- dialog <prompt-id> accept "Literal response"
notch-browser action --tab <tab-id> -- dialog <dialog-id> dismiss
```

JavaScript alerts, confirms and prompts can be answered by ID. IDs prevent a
stale command from answering a replacement dialog. Native sheets continue to
work manually, and the prepared-image file-picker configuration for Lens is
preserved. Answering a page dialog still follows the user's authorized task.

`blockers` reports native pending dialogs and best-effort detection of common
human-verification pages/widgets. Widget presence does not prove a challenge is
unsolved. Verification response tokens are redacted from snapshots/text, and
automated actions in recognized challenge documents/controls return
`human_required`; CAPTCHA solving is not implemented.

Website camera/microphone requests show their origin and require the user's
native Allow/Don't Allow choice. The `dialog` command cannot answer these
permission requests. Enter defaults to Don't Allow. macOS can additionally show its own
permission prompt, which the CLI cannot enumerate or answer. Use `handoff` to
select/reveal the tab and pause agent control; after completing the manual step,
the user presses Resume in the app. Navigation/tab closure cancels pending
requests, and license revocation cancels pending requests across all tabs.

```sh
notch-browser action --tab <tab-id> --json -- blockers
notch-browser action --tab <tab-id> -- handoff
```

## Extracting pages and media references

Use `extract` to collect an article, product page, or loaded social post as
structured JSON without writing site-specific JavaScript:

```sh
notch-browser action --session research --tab <tab-id> --json -- extract
notch-browser action --session research --tab <tab-id> --max-chars 20000 --limit 20 --json -- extract "article"
notch-browser action --session research --tab <tab-id> --json -- media-frame @m<extraction>-1 /absolute/path/frame.png
```

The versioned extraction includes readable text, headings, links, image URLs,
page metadata, selected publisher structured data, and visible audio/video
elements. Media includes source type, playback state, duration when known,
loaded subtitle/caption cues, and declared caption-file URLs. Publisher
transcripts are identified separately. Passwords and form values are excluded.
The optional selector scopes DOM content; page metadata describes the whole
page. By default extraction uses the first visible main/article region, then
falls back to the body. It does not expand posts or scroll a feed.

`--max-chars` bounds readable text and, separately, the combined transcript/cue
text. `--limit` bounds each collection to at most 50 items; media and structured
data have a further cap of 10. `truncated` and `limitations` describe incomplete
results. Child-frame content is not merged into its parent; use `--frame` to
extract that frame separately. Shadow-root content is omitted. No network
requests are made by extraction.

Use a full `@m...` reference from the latest extraction with `media-frame` to
save the currently decoded video frame. PNG dimensions are capped at 1280 px on
the longest side. Playback, scrolling and caption modes are preserved. A new
extraction, navigation, node removal or changed source expires the reference;
ordinary semantic snapshots do not. Direct frame capture may be blocked by a
site's cross-origin rules (`frame_access_denied`) or media protection
(`media_protected`); a video without a decoded frame returns `frame_unavailable`.
Use a page screenshot to inspect the rendered page when appropriate. Blob
media URLs are tab-local identifiers, not downloadable files.

These commands provide source material for an agent to analyze. They do not
download entire videos, perform speech transcription, or generate new media.
Authenticated Instagram and other third-party flows require separate live
verification; fixture tests establish the generic extraction behavior.

## Results and recovery

Options go before `--`; page-command arguments after it are literal values.
`--json` emits one result envelope to stdout. Successful commands exit 0,
failed commands exit 1. Both include a protocol version and request ID.

```json
{"id":"request-id","protocolVersion":1,"ok":true,"data":{"tabId":"tab-id"}}
```

Errors contain a stable `error.code` and readable `error.message`.

- `stale_ref`: take a fresh snapshot for element refs, or a new extraction for media refs.
- `tab_gone`: choose an explicit existing tab or open a new one.
- `busy`: a command is running; wait for it to finish before retrying.
- `agent_paused`: the user stopped agent control; resume through the app UI.
- `license_required`: activate the app using its normal license flow.
- `timeout`: navigation/wait did not finish; the tab remains open for inspection.
- `javascript_timeout`: a page script did not respond; close an unresponsive tab.
- `result_too_large`: reduce collection/text limits, narrow an extraction selector, or return a smaller eval result.
- `frame_gone`: run `frames` and snapshot the new frame ID.
- `dialog_pending`: run `dialogs`; respond to the identified page dialog or file picker.
- `dialog_gone`: the dialog was already answered/closed; inspect current dialogs.
- `human_required`: reveal the tab with `handoff` and let the user complete the step.
- `file_picker_unavailable`: no files were supplied; try the site's custom upload button and native dialog flow.

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
not WebKit's full native accessibility tree. Some sites requiring physical input,
closed shadow roots, browser/system permission approval, download management,
and CAPTCHA solving still require human interaction. Network interception,
recording, separate profiles and MCP registration are not included.

## Verification

```sh
python3 notch-browser/AgentTools/Tests/integration.py
```

The test runner compiles a separate native app from the production tab models,
controller, DOM bridge, and socket code. It replaces only licensing and session
storage with fixtures, uses an ephemeral WebKit data store, and drives the real
CLI against local pages. It checks form events and literal values, references,
background navigation, tab pinning, popups, screenshots, history, wait/eval
bounds, scoped extraction, metadata, captions, synthetic video frame capture,
cross-origin/nested frames, native single/multiple uploads, hidden upload buttons,
JavaScript dialog responses, manual permission/verification handoff, Stop/Resume,
license enforcement, and protocol errors. It never reads
real account cookies or license keys. These checks do not establish behavior
on authenticated third-party sites.
