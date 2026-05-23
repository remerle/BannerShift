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
  let perms =
    try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
  #expect(perms.intValue == 0o600)
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
