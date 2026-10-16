# Quick lookup

Quick lookup opens a temporary tab in the notch while keeping your existing tabs in place.

## Text

- Select text in another app, then choose **Services → Search in Notch** or **Translate in Notch** from that app's menu or context menu.
- Or copy text and press **Control–Shift–Space**. **Look Up Clipboard** is also available in Notch Browser's menu-bar menu and **Browser** menu.
- Use the lookup's destination menu to switch between your chosen search engine, definitions, Google Translate, and MDN documentation. Translation initially targets your Mac's language.
- Press **Esc** or the lookup's close button to return to the app you were using. Choosing **Keep as a regular tab** retains the result instead.

The clipboard action reads only when invoked and does not change the clipboard. It accepts up to 4,000 UTF-16 code units of text. The global shortcut can be disabled with **Enable Clipboard Shortcut**. If another app owns that shortcut, the menu explains the conflict and the menu and Services actions remain available. The shortcut uses macOS hotkey registration and does not request Accessibility permission.

## Images and Google Lens

- Copy an image and press **Control–Shift–Space**, or select an image file in Finder and choose **Services → Search Image in Notch**.
- Check the local preview, then click **Search with Google Lens** to send the prepared image to Google and view the results in the notch.
- **Search Screen Region with Lens…** starts macOS's region selector. Select an area, or press Esc to cancel. This capture path may require Screen Recording permission; copying an image works without screen capture.
- If Google's upload interface changes or fails to accept the automatic handoff, open its image upload area and drag the small prepared thumbnail into it. Its file chooser also starts in the prepared image's directory.

Images are limited to 25 MiB on input, reduced to at most 1,600 pixels on their longest side, and re-encoded as PNG. Prepared files are held in a private temporary directory and removed when the lookup releases them. Opening the preview does not upload the image; searching does. Lens uses Google's normal image-search website and your existing browser session.

## Temporary tab behavior

Repeated lookups reuse a single temporary tab. Closing it restores the prior tab and toolbar visibility. Temporary tabs are omitted from saved sessions and the reopen-closed-tab list. Switching to another tab also cleans up the temporary lookup. **Keep as a regular tab** makes the result part of normal tab/session restoration.

Lookup still uses the ordinary browsing profile, cookies, and history. It is not a private-browsing mode.

## Development checks

```sh
python3 Scripts/test-notch-browser.py --suite lookup
python3 Scripts/test-notch-browser.py --suite session
swift test --disable-sandbox
```

The lookup suite uses a private test clipboard, local pages, and disposable tab/defaults state. It checks Services declarations, query encoding, tab lifecycle, clipboard preservation, bounded image preparation, upload origin checks, delayed-upload cancellation, and the registered Carbon event handler. Live Google Lens and native Services checks are recorded separately from fixture tests.

Services are declared in `NotchBrowser-Info.plist`. Each declaration includes `NSRequiredContext`, and the Finder action declares `NSSendFileTypes = public.image`; see Apple's [Services Properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html). A distributed app should be installed in Applications. During development, Launch Services may need its registration refreshed after changing these declarations; an already-running source app may need reopening before its Services menu updates.
