import CoreGraphics
import Testing

@testable import BannerShiftCore

private let primary = ScreenInfo(
  frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
  visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
  isPrimary: true
)

private let secondaryRight = ScreenInfo(
  frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
  visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
  isPrimary: false
)

private let secondaryAbove = ScreenInfo(
  // Physically above primary => positive AppKit y.
  frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
  visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
  isPrimary: false
)

@Test func pointInPrimaryReturnsPrimary() {
  // AX-space window center on primary: (960, 540) in AX coords (top-left origin).
  let selector = DisplaySelector(screens: [primary, secondaryRight])
  let screen = selector.screenContaining(axPoint: CGPoint(x: 960, y: 540))
  #expect(screen == primary)
}

@Test func pointInSecondaryReturnsSecondary() {
  let selector = DisplaySelector(screens: [primary, secondaryRight])
  let screen = selector.screenContaining(axPoint: CGPoint(x: 2880, y: 540))
  #expect(screen == secondaryRight)
}

@Test func pointAboveUsesPrimaryHeightAsFlipPivot() {
  // AX y=-500 is physically 500pt above the primary display top.
  // Using primary height as pivot, AppKit y = 1080 - (-500) = 1580
  // which lands in secondaryAbove (frame y=1080..2160). Correct.
  // If we incorrectly used the global max y (1080+1080=2160) as pivot,
  // AppKit y = 2160 - (-500) = 2660 — falls in NO screen. Wrong.
  let selector = DisplaySelector(screens: [primary, secondaryAbove])
  let screen = selector.screenContaining(axPoint: CGPoint(x: 960, y: -500))
  #expect(screen == secondaryAbove)
}

@Test func pointOutsideFallsBackToActiveScreen() {
  let selector = DisplaySelector(screens: [primary, secondaryRight])
  let fallback = ScreenInfo(
    frame: CGRect(x: 0, y: 0, width: 100, height: 100),
    visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
    isPrimary: false
  )
  // Way off any display.
  let screen = selector.screenContaining(
    axPoint: CGPoint(x: 99999, y: 99999),
    activeScreenFallback: fallback
  )
  #expect(screen == fallback)
}

@Test func fallbackToPrimaryWhenNoActiveScreen() {
  let selector = DisplaySelector(screens: [primary, secondaryRight])
  let screen = selector.screenContaining(
    axPoint: CGPoint(x: 99999, y: 99999),
    activeScreenFallback: nil
  )
  #expect(screen == primary)
}

@Test func emptyScreensReturnsNil() {
  let selector = DisplaySelector(screens: [])
  #expect(selector.screenContaining(axPoint: .zero) == nil)
}
