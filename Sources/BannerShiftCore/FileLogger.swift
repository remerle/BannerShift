import Foundation

// `BannerShiftCore` is otherwise free of system-API dependencies, but
// `FileLogger` is the deliberate exception: it lives here so the rest of Core
// (Preferences, RuleStore, etc.) can use it without creating a circular
// dependency through the executable target. The Foundation imports below are
// intentional and limited to file I/O; the "no system-API deps" convention
// refers to AppKit/AX APIs specifically, not Foundation.

/// Append-only file logger.
///
/// - File is created with 0600 permissions and the write handle is held open
///   for the lifetime of the logger.
/// - Each line is prefixed with a level tag and an ISO-8601 timestamp.
/// - `debug` calls are gated on a live closure check so toggling the debug
///   preference via `defaults write` takes effect without relaunch.
/// - At construction, if the file exceeds `Constants.maxLogFileSize` it is
///   truncated.
public final class FileLogger {
  public enum Level: String {
    case info = "INFO"
    case debug = "DEBUG"
    case error = "ERROR"
  }

  private let url: URL
  private let handle: FileHandle
  private let isDebugEnabled: () -> Bool
  private let formatter: ISO8601DateFormatter
  private let queue = DispatchQueue(label: "BannerShift.FileLogger")
  /// Set to `true` inside `close()` under the `queue.sync` barrier. Read only
  /// inside the serial-queue closure in `write(_:_:)`, so no further
  /// synchronization is needed.
  private var closed = false

  /// - Parameters:
  ///   - url: Destination log file. Parent directory is created if missing.
  ///   - isDebugEnabled: Live check evaluated on every `debug(_:)` call so
  ///     the debug flag can be flipped at runtime.
  public init(url: URL, isDebugEnabled: @escaping () -> Bool) throws {
    self.url = url
    self.isDebugEnabled = isDebugEnabled
    self.formatter = ISO8601DateFormatter()
    self.formatter.formatOptions = [.withInternetDateTime]

    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let fm = FileManager.default
    if let attrs = try? fm.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? Int, size > Constants.maxLogFileSize
    {
      // Propagate removal failures: AppDelegate catches init errors and
      // terminates (fail-fast), which is preferable to silently appending to
      // a permanently oversized file.
      try fm.removeItem(at: url)
    }

    if !fm.fileExists(atPath: url.path) {
      fm.createFile(
        atPath: url.path, contents: nil,
        attributes: [.posixPermissions: NSNumber(value: 0o600)])
    } else {
      try? fm.setAttributes(
        [.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
    }

    self.handle = try FileHandle(forWritingTo: url)
    self.handle.seekToEndOfFile()
  }

  /// Write an INFO-level message.
  public func info(_ message: String) { write(.info, message) }

  /// Write an ERROR-level message.
  public func error(_ message: String) { write(.error, message) }

  /// Write a DEBUG-level message if `isDebugEnabled()` returns true at call time.
  public func debug(_ message: String) {
    guard isDebugEnabled() else { return }
    write(.debug, message)
  }

  /// Drain pending writes and close the file handle. Safe to call once.
  /// After this returns, subsequent `info`/`debug`/`error` calls are an
  /// explicit no-op (rather than a silent failed write to a closed handle).
  public func close() {
    queue.sync {
      self.closed = true
      try? self.handle.close()
    }
  }

  private func write(_ level: Level, _ message: String) {
    let line = "[\(level.rawValue)] \(formatter.string(from: Date())) \(message)\n"
    queue.async {
      guard !self.closed else { return }
      if let data = line.data(using: .utf8) {
        try? self.handle.write(contentsOf: data)
      }
    }
  }
}
