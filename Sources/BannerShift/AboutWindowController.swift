import AppKit

final class AboutWindowController {
  private var window: NSWindow?

  func show() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let info = Bundle.main.infoDictionary ?? [:]
    let version = (info["CFBundleShortVersionString"] as? String) ?? "—"
    let copyright = (info["NSHumanReadableCopyright"] as? String) ?? ""
    let name = (info["CFBundleName"] as? String) ?? "BannerShift"

    let frame = NSRect(x: 0, y: 0, width: 320, height: 220)
    let style: NSWindow.StyleMask = [.titled, .closable]
    let w = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
    w.title = ""
    w.isReleasedWhenClosed = false
    w.center()

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    if let icon = NSApp.applicationIconImage {
      let iv = NSImageView(image: icon)
      iv.translatesAutoresizingMaskIntoConstraints = false
      iv.widthAnchor.constraint(equalToConstant: 64).isActive = true
      iv.heightAnchor.constraint(equalToConstant: 64).isActive = true
      stack.addArrangedSubview(iv)
    }
    let nameLabel = label(name, weight: .semibold, size: 16)
    let versionLabel = label("Version \(version)", weight: .regular, size: 12)
    let maintainer = label("Maintainer: Ryan Emerle", weight: .regular, size: 11)
    let copyLabel = label(copyright, weight: .regular, size: 11)
    copyLabel.maximumNumberOfLines = 2

    stack.addArrangedSubview(nameLabel)
    stack.addArrangedSubview(versionLabel)
    stack.addArrangedSubview(maintainer)
    stack.addArrangedSubview(copyLabel)

    let content = NSView(frame: frame)
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    w.contentView = content
    window = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func label(_ text: String, weight: NSFont.Weight, size: CGFloat) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = NSFont.systemFont(ofSize: size, weight: weight)
    f.alignment = .center
    return f
  }
}
