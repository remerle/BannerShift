import AppKit
import BannerShiftCore

/// Owns the in-memory pinned-notifications list and the always-on-top panel
/// that renders it.
///
/// `capture(_:)` is the single entry point, called on the main thread from
/// `BannerMover`'s `onPin` callback. The panel is a non-activating floating
/// `NSPanel`: it sits above other apps' windows, follows the user across
/// Spaces, shows over full-screen apps, and never steals keyboard focus when
/// a row is clicked. It is shown when the list becomes non-empty and ordered
/// out when the last item is dismissed. AppKit, main-thread only.
final class ReminderController: NSObject, NSWindowDelegate {
  private var list = PinnedList()
  private let preferences: Preferences
  private var panel: NSPanel?
  private let stack = NSStackView()
  /// True once the panel has been placed at its initial top-right default.
  ///
  /// Prevents re-snapping to top-right when the panel resizes after the
  /// user has dragged it to a different position.
  private var hasPositioned = false

  init(preferences: Preferences) {
    self.preferences = preferences
    super.init()
  }

  /// Capture one notification into the list and refresh the panel.
  func capture(_ notification: CapturedNotification) {
    list.pin(notification)
    render()
  }

  // MARK: List mutations from the UI

  @objc private func dismissRow(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    list.dismiss(id: id)
    render()
  }

  @objc private func dismissAll() {
    list.dismissAll()
    render()
  }

  @objc private func openSourceApp(_ sender: NSClickGestureRecognizer) {
    guard let bundleID = sender.view?.identifier?.rawValue, !bundleID.isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  // MARK: Rendering

  /// Rebuild the row views from the current list and show or hide the panel.
  ///
  /// After rebuilding the rows the panel is resized to fit its content, capped
  /// to the visible screen height so it never exceeds the display. When no
  /// saved origin exists the panel is placed at the top-right of the screen
  /// AFTER sizing, so the placement uses the real panel dimensions.
  private func render() {
    if list.isEmpty {
      panel?.orderOut(nil)
      return
    }
    let panel = ensurePanel()
    for view in stack.arrangedSubviews { view.removeFromSuperview() }
    for item in list.items {
      stack.addArrangedSubview(rowView(for: item))
    }
    stack.addArrangedSubview(footerView())

    // Give the clip view a resolved width before measuring: on the first
    // render the panel has never been laid out, so the stack's width (tied to
    // the clip view) is still 0 and `fittingSize.height` would be degenerate.
    // A generous scratch height establishes the 320pt content width first.
    panel.setContentSize(NSSize(width: 320, height: 4000))
    stack.layoutSubtreeIfNeeded()
    let contentHeight = stack.fittingSize.height
    let screen = panel.screen ?? NSScreen.main
    // Floor the cap so a pathologically short screen can't yield a negative
    // (which setContentSize would clamp to a title-bar-only sliver).
    let maxHeight = max(100, (screen?.visibleFrame.height ?? 800) - 80)
    panel.setContentSize(NSSize(width: 320, height: min(contentHeight, maxHeight)))

    // Apply the default top-right placement once, after the panel has its real
    // size. Subsequent renders keep the user's dragged position.
    if !hasPositioned && preferences.pinnedPanelOrigin == nil {
      positionTopRight(panel)
      hasPositioned = true
    }

    panel.orderFrontRegardless()  // show without activating BannerShift
  }

  /// Build a single row: app name + count badge, title, truncated body, and a dismiss button.
  ///
  /// Clicking the row (outside the button) opens the app.
  private func rowView(for item: PinnedItem) -> NSView {
    let appTitle = item.count > 1 ? "\(item.appName) · \(item.count)" : item.appName
    let appLabel = makeLabel(appTitle, weight: .semibold, size: 12)
    let titleLabel = makeLabel(item.title, weight: .regular, size: 12)
    let bodyLabel = makeLabel(item.body, weight: .regular, size: 11)
    bodyLabel.textColor = .secondaryLabelColor
    bodyLabel.lineBreakMode = .byTruncatingTail
    bodyLabel.maximumNumberOfLines = 2

    let text = NSStackView(views: [appLabel, titleLabel, bodyLabel])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2
    text.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let dismiss = NSButton(title: "\u{00D7}", target: self, action: #selector(dismissRow(_:)))
    dismiss.bezelStyle = .circular
    dismiss.identifier = NSUserInterfaceItemIdentifier(item.id)
    dismiss.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    let row = NSStackView(views: [text, dismiss])
    row.orientation = .horizontal
    row.alignment = .top
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    // Row click opens the source app; carry the bundle ID on the row's
    // identifier so the gesture handler can resolve it. Empty when unknown.
    row.identifier = NSUserInterfaceItemIdentifier(item.bundleID ?? "")
    let click = NSClickGestureRecognizer(target: self, action: #selector(openSourceApp(_:)))
    row.addGestureRecognizer(click)
    return row
  }

  /// Trailing "Dismiss All" footer button.
  private func footerView() -> NSView {
    let button = NSButton(title: "Dismiss All", target: self, action: #selector(dismissAll))
    button.bezelStyle = .rounded
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let footer = NSStackView(views: [spacer, button])
    footer.orientation = .horizontal
    footer.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 8, right: 10)
    return footer
  }

  private func makeLabel(_ text: String, weight: NSFont.Weight, size: CGFloat) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    return field
  }

  // MARK: Panel construction

  /// Lazily build the floating panel, restoring its saved origin.
  ///
  /// The row stack lives inside a vertical `NSScrollView` so the panel can cap
  /// its height to the screen and still let the user scroll through long lists.
  /// Panel sizing is deferred to `render()` so the first placement uses the
  /// real content height.
  private func ensurePanel() -> NSPanel {
    if let panel { return panel }

    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
    stack.translatesAutoresizingMaskIntoConstraints = false

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = stack

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
      styleMask: [.titled, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.title = "Pinned Notifications"
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.delegate = self

    // NSPanel always provides a contentView for a buffered (non-deferred)
    // panel. A nil here indicates a serious AppKit initialisation failure;
    // bail loudly rather than silently producing a broken UI.
    guard let content = panel.contentView else {
      preconditionFailure("NSPanel has no contentView after buffered init")
    }
    content.addSubview(scrollView)

    let clipView = scrollView.contentView

    NSLayoutConstraint.activate([
      // Scroll view fills the panel's content area.
      scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: content.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      // Stack matches the clip view's width (pinned leading) so only vertical
      // scrolling occurs. Width + leading fully determine the horizontal axis;
      // a trailing constraint too would over-determine it and risk solver noise
      // as the clip view's width changes during scroll.
      stack.widthAnchor.constraint(equalTo: clipView.widthAnchor),
      stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      stack.topAnchor.constraint(equalTo: clipView.topAnchor),
      // No bottom constraint: lets the stack grow past the clip view's height,
      // which is what makes vertical scrolling possible.
    ])

    // Restore a previously saved dragged position. If none exists, the default
    // top-right placement is applied in render() after the panel is sized.
    if let origin = preferences.pinnedPanelOrigin {
      panel.setFrameOrigin(origin)
      hasPositioned = true
    }

    self.panel = panel
    return panel
  }

  /// Default placement: top-right of the main screen's visible area.
  ///
  /// Falls back to `panel.center()` when `NSScreen.main` is unavailable
  /// (e.g. the display list is momentarily empty during sleep/wake).
  private func positionTopRight(_ panel: NSPanel) {
    guard let screen = NSScreen.main else {
      panel.center()
      return
    }
    let visible = screen.visibleFrame
    let size = panel.frame.size
    let origin = CGPoint(
      x: visible.maxX - size.width - 20,
      y: visible.maxY - size.height - 20)
    panel.setFrameOrigin(origin)
  }

  // MARK: NSWindowDelegate

  /// Remember the dragged position (origin only — not notification content).
  func windowDidMove(_ notification: Notification) {
    guard let panel else { return }
    preferences.pinnedPanelOrigin = panel.frame.origin
  }
}
