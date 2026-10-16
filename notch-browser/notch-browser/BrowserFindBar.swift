import SwiftUI

struct BrowserFindBar: View {
    @ObservedObject var browser: BrowserModel
    var body: some View {
        HStack(spacing: 10) {
            BrowserAddressField(text: $browser.findQuery, font: .systemFont(ofSize: 12), textColor: .white,
                                placeholder: "Find in page", onSubmit: { browser.findNext() },
                                focusRequest: browser.findFocusRequest, accessibilityLabel: "Find in page",
                                accessibilityIdentifier: "notch-browser-find", resignOnSubmit: false,
                                onFocusHandled: browser.consumeFindFocus,
                                onCancel: browser.hideFind)
                .padding(7)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            if browser.findMatchFound == false {
                Text("No matches").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
            Button { browser.findNext(backwards: true) } label: { Image(systemName: "chevron.up").frame(width: 24, height: 24) }
                .accessibilityLabel("Previous match")
            Button { browser.findNext() } label: { Image(systemName: "chevron.down").frame(width: 24, height: 24) }
                .accessibilityLabel("Next match")
            Button(action: browser.hideFind) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                .accessibilityLabel("Close find")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.black)
    }
}
