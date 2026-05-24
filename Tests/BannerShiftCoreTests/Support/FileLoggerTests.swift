import Foundation
import Testing

@testable import BannerShiftCore

private func tempLogURL() -> URL {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("bsh-logs-\(UUID().uuidString)")
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir.appendingPathComponent("BannerShift.log")
}

@Test func writesInfoAlways() throws {
  let url = tempLogURL()
  let debug = false
  let logger = try FileLogger(url: url, isDebugEnabled: { debug })
  logger.info("hello")
  logger.close()
  let contents = try String(contentsOf: url)
  #expect(contents.contains("INFO"))
  #expect(contents.contains("hello"))
}

@Test func skipsDebugWhenDisabled() throws {
  let url = tempLogURL()
  let logger = try FileLogger(url: url, isDebugEnabled: { false })
  logger.debug("secret")
  logger.close()
  let contents = try String(contentsOf: url)
  #expect(!contents.contains("secret"))
}

@Test func writesDebugWhenEnabled() throws {
  let url = tempLogURL()
  var debug = false
  let logger = try FileLogger(url: url, isDebugEnabled: { debug })
  debug = true
  logger.debug("visible")
  logger.close()
  let contents = try String(contentsOf: url)
  #expect(contents.contains("DEBUG"))
  #expect(contents.contains("visible"))
}

@Test func createsFileWith0600() throws {
  let url = tempLogURL()
  let logger = try FileLogger(url: url, isDebugEnabled: { false })
  logger.info("x")
  logger.close()
  // POSIX permissions on macOS come back as an NSNumber-bridged value;
  // `as? Int` extracts the underlying integer regardless of the bridging
  // representation, avoiding both force-cast and the legacy NSNumber type.
  let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
  #expect(perms as? Int == 0o600)
}

@Test func truncatesOversizedFileAtLaunch() throws {
  let url = tempLogURL()
  let big = String(repeating: "x", count: Constants.maxLogFileSize + 1024)
  try big.write(to: url, atomically: true, encoding: .utf8)
  let logger = try FileLogger(url: url, isDebugEnabled: { false })
  logger.info("fresh")
  logger.close()
  let contents = try String(contentsOf: url)
  #expect(contents.count < Constants.maxLogFileSize)
  #expect(contents.contains("fresh"))
  #expect(!contents.contains("xxxxxxxxxx"))
}

@Test func linesHaveISOTimestampAndLevel() throws {
  let url = tempLogURL()
  let logger = try FileLogger(url: url, isDebugEnabled: { false })
  logger.error("oh no")
  logger.close()
  let contents = try String(contentsOf: url)
  #expect(contents.contains("ERROR"))
  #expect(contents.range(of: #"\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil)
}

/// Records what the logger routes to the unified-log sink.
///
/// The logger only invokes the sink on its serial queue, and `close()` is
/// a `queue.sync` barrier, so reading `calls` after `close()` is safe.
private final class SinkSpy {
  var calls: [(FileLogger.Level, String)] = []
  func record(_ level: FileLogger.Level, _ message: String) {
    calls.append((level, message))
  }
}

@Test func mirrorsInfoAndErrorToUnifiedLog() throws {
  let spy = SinkSpy()
  let logger = try FileLogger(
    url: tempLogURL(), isDebugEnabled: { true }, unifiedLogSink: spy.record)
  logger.info("up")
  logger.error("bad")
  logger.close()
  #expect(spy.calls.contains { $0.0 == .info && $0.1 == "up" })
  #expect(spy.calls.contains { $0.0 == .error && $0.1 == "bad" })
}

@Test func neverMirrorsDebugToUnifiedLog() throws {
  // Security invariant: DEBUG is the only level that may carry notification
  // content, so it must never reach the unified log — only the gated file.
  let url = tempLogURL()
  let spy = SinkSpy()
  let logger = try FileLogger(
    url: url, isDebugEnabled: { true }, unifiedLogSink: spy.record)
  logger.debug("notification body text")
  logger.close()
  #expect(spy.calls.isEmpty)
  // ...but it is still written to the gated on-disk file.
  let contents = try String(contentsOf: url)
  #expect(contents.contains("notification body text"))
}
