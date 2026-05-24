import Foundation
import OSLog

// `BannerShiftCore` is otherwise free of system-API dependencies, but
// `FileLogger` is the deliberate exception: it lives here so the rest of Core
// (Preferences, RuleStore, etc.) can use it without creating a circular
// dependency through the executable target. The Foundation and OSLog imports
// below are intentional and limited to file I/O plus the unified-log mirror;
// the "no system-API deps" convention refers to AppKit/AX APIs specifically.

/// Append-only file logger that is the system of record for diagnostics,
/// with a one-way mirror of non-sensitive lines into the unified log.
///
/// Why a custom file logger rather than plain `os.Logger`: BannerShift
/// reads notification content via Accessibility, and the privacy contract
/// is *fail-closed* — notification text must never reach disk (or any
/// system log) unless the user opts into debug logging. A gated plaintext
/// file gives an auditable "we don't write it" guarantee and a `tail`-able
/// file for bug reports, neither of which `os.Logger`'s redaction model and
/// proprietary store provide. To still behave like a good macOS citizen,
/// `info`/`error` (which carry only operational text) are also mirrored to
/// the unified log so the agent shows up in Console and `sysdiagnose`;
/// `debug` is the only level that may carry content and is **never**
/// mirrored.
///
/// - File is created with 0600 permissions and the write handle is held open
///   for the lifetime of the logger.
/// - Each line is prefixed with a level tag and an ISO-8601 timestamp.
/// - `debug` calls are gated on a live closure check so toggling the debug
///   preference via `defaults write` takes effect without relaunch.
/// - At construction, if the file exceeds `Constants.maxLogFileSize` it is
///   truncated.
public final class FileLogger {
  /// Sink for log lines mirrored into the system's unified log.
  ///
  /// Injectable through the designated initializer so the level-routing
  /// invariant (info/error mirrored, `debug` never) can be unit-tested
  /// without reading back the privileged, hard-to-read unified-log store.
  typealias UnifiedLogSink = (Level, String) -> Void

  /// Severity tag emitted at the start of each log line.
  public enum Level: String {
    /// Routine operational event (launch, AX events, rule load count).
    case info = "INFO"

    /// Verbose diagnostic, including notification content. Gated by the
    /// debug-logging preference at write time so the default install
    /// never spills notification text to disk, and never mirrored to the
    /// unified log.
    case debug = "DEBUG"

    /// Recoverable failure the user might need to act on (AX denied,
    /// malformed rule pattern, log-file write failure).
    case error = "ERROR"
  }

  private let url: URL
  private let handle: FileHandle
  private let isDebugEnabled: () -> Bool
  private let formatter: ISO8601DateFormatter
  private let queue = DispatchQueue(label: "BannerShift.FileLogger")
  // Unified-log handle, used both to mirror non-sensitive lines (via
  // `mirror`) and as the last-resort sink when a file write fails (disk
  // full, EPERM after permission revocation, etc.); without it a
  // diagnostic after a file failure would silently disappear.
  private let osLog: Logger
  // Mirror of non-sensitive log lines into the unified log. See
  // `UnifiedLogSink`; `debug` is never routed here.
  private let mirror: UnifiedLogSink
  /// Set to `true` inside `close()` under the `queue.sync` barrier.
  ///
  /// Read only inside the serial-queue closure in `write(_:_:)`, so no
  /// further synchronization is needed.
  private var closed = false

  /// - Parameters:
  ///   - url: Destination log file. Parent directory is created if
  ///     missing; the file is created with mode 0600 on first launch
  ///     and re-asserted to 0600 on subsequent launches.
  ///   - isDebugEnabled: Live check evaluated on every `debug(_:)` call
  ///     so the debug flag can be flipped at runtime.
  /// - Throws: Rethrows directory-creation, file-removal, or
  ///   file-handle errors from `FileManager`/`FileHandle`. Callers
  ///   should treat any throw as fatal (the app cannot run without a
  ///   working log) and terminate.
  public convenience init(url: URL, isDebugEnabled: @escaping () -> Bool) throws {
    try self.init(url: url, isDebugEnabled: isDebugEnabled, unifiedLogSink: nil)
  }

  /// Designated initializer with an injectable unified-log sink.
  ///
  /// - Parameters:
  ///   - url: Destination log file; see the convenience initializer.
  ///   - isDebugEnabled: Live debug-gate check; see the convenience initializer.
  ///   - unifiedLogSink: Sink for mirrored info/error lines. `nil` selects
  ///     the default `os.Logger`-backed sink (`info` → `.notice`, `error` →
  ///     `.error`, both `.public`); tests pass a spy to assert routing.
  /// - Throws: Rethrows directory-creation, file-removal, or file-handle
  ///   errors; callers should treat any throw as fatal.
  init(
    url: URL,
    isDebugEnabled: @escaping () -> Bool,
    unifiedLogSink: UnifiedLogSink?
  ) throws {
    self.url = url
    self.isDebugEnabled = isDebugEnabled
    self.formatter = ISO8601DateFormatter()
    self.formatter.formatOptions = [.withInternetDateTime]
    let log = Logger(subsystem: Constants.bundleIdentifier, category: "agent")
    self.osLog = log
    self.mirror =
      unifiedLogSink
      ?? { level, message in
        switch level {
        case .info: log.notice("\(message, privacy: .public)")
        case .error: log.error("\(message, privacy: .public)")
        case .debug: break  // unreachable: write() never mirrors debug
        }
      }

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
        attributes: [.posixPermissions: 0o600])
    } else {
      try? fm.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: url.path)
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

  /// Drain pending writes and close the file handle.
  ///
  /// Idempotent: a second call is a silent no-op. After this returns,
  /// subsequent `info`/`debug`/`error` calls are an explicit no-op
  /// (rather than a silent failed write to a closed handle).
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
      // Mirror non-sensitive levels to the unified log so the agent is
      // observable in Console / sysdiagnose. DEBUG is never mirrored: it is
      // the only level that may carry notification content, which stays in
      // the gated on-disk file.
      if level != .debug {
        self.mirror(level, message)
      }
      guard let data = line.data(using: .utf8) else { return }
      do {
        try self.handle.write(contentsOf: data)
      } catch {
        // The file is the system of record; info/error already reached the
        // unified log above. For debug we surface only the failure, never
        // the (potentially sensitive) message, so a broken file handle
        // cannot spill notification content into the unified log. We keep
        // attempting future file writes since the failure may be transient
        // (e.g. brief disk pressure).
        if level == .debug {
          self.osLog.error(
            "FileLogger: debug write failed (\(error.localizedDescription, privacy: .public))"
          )
        } else {
          self.osLog.error(
            "FileLogger: write failed (\(error.localizedDescription, privacy: .public))"
          )
        }
      }
    }
  }
}
