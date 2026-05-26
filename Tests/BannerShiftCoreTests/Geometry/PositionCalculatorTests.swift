import CoreGraphics
import Testing

@testable import BannerShiftCore

private let screen = ScreenInfo(
  frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
  visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),  // 25pt Dock inset (bottom)
  isPrimary: true
)
private let primaryHeight: CGFloat = 1080

/// A typical banner: window is full screen, banner sits in the top-right
/// inside the window, 360x80, with 16pt right inset.
private let windowFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
private let bannerFrame = CGRect(x: 1544, y: 0, width: 360, height: 80)

private func makeCalc(
  windowFrame: CGRect = windowFrame,
  bannerFrame: CGRect = bannerFrame,
  screen: ScreenInfo = screen,
  primaryHeight: CGFloat = primaryHeight
) -> PositionCalculator {
  PositionCalculator(
    windowFrame: windowFrame,
    bannerFrame: bannerFrame,
    screen: screen,
    primaryHeight: primaryHeight
  )
}

@Test func topRightLeavesOriginUntouched() {
  // Semantic assertion: .topRight returns the OS-placed window origin
  // unchanged. The fixture's windowFrame happens to start at .zero but
  // the contract is "preserve windowFrame.origin", not "return zero".
  let origin = makeCalc().targetOrigin(for: .topRight)
  #expect(origin.x == windowFrame.origin.x)
  #expect(origin.y == windowFrame.origin.y)
}

@Test func topLeftShiftsWindowLeftByBannerOffset() {
  // Want banner left at screen x=0. Banner is at window x=1544; want it at 0.
  // So window origin x = 0 - 1544 = -1544.
  let origin = makeCalc().targetOrigin(for: .topLeft)
  #expect(origin.x == -1544)
  #expect(origin.y == 0)
}

@Test func topMiddleCentersBannerHorizontally() {
  // Centered banner left = (1920 - 360) / 2 = 780.
  // Banner offset inside window = 1544.
  // Window origin x = 780 - 1544 = -764.
  let origin = makeCalc().targetOrigin(for: .topMiddle)
  #expect(origin.x == -764)
  #expect(origin.y == 0)
}

@Test func bottomRightShiftsWindowUp() {
  // visibleTopAX = 1080 - 1080 = 0
  // visibleBottomAX = 1080 - 25 = 1055
  // banner bottom should land at 1055 - 30 = 1025
  // banner bottom in window = bannerFrame.maxY = 0 + 80 = 80
  // window y = 1025 - 80 = 945
  let origin = makeCalc().targetOrigin(for: .bottomRight)
  #expect(origin.x == 0)
  #expect(origin.y == 945)
}

@Test func middleCentersVerticallyOnVisibleArea() {
  // .middle is horizontal=.center, vertical=.middle.
  // Horizontal: same as topMiddle — centered banner left = (1920 - 360) / 2 = 780,
  // banner offset = 1544, so window origin x = 780 - 1544 = -764.
  // Vertical:
  //   visibleTopAX = 0, visibleBottomAX = 1055.
  //   visibleCenterAX = (0 + 1055) / 2 = 527.5
  //   bannerCenter_in_window = (0 + 80) / 2 = 40
  //   target window y = 527.5 - 40 - dockPadding/2 = 527.5 - 40 - 15 = 472.5 → rounded to 473
  let origin = makeCalc().targetOrigin(for: .middle)
  #expect(origin.x == -764)
  #expect(origin.y == 473)
}

@Test func targetOriginIsSnappedToIntegers() {
  let origin = makeCalc(
    windowFrame: CGRect(x: 0, y: 0, width: 1921, height: 1081),
    bannerFrame: CGRect(x: 1545, y: 0, width: 361, height: 81)
  ).targetOrigin(for: .topMiddle)
  #expect(origin.x == origin.x.rounded())
  #expect(origin.y == origin.y.rounded())
}

@Test func windowHeightMismatchIsRejected() {
  // Guard against the OS's full-screen container window invariant
  // breaking: notification UI windows are always exactly the height of
  // the display they live on. If that stops holding (an OS change), our
  // coordinate math is unsafe and we refuse to reposition.
  let calc = makeCalc(
    windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 800)  // wrong height
  )
  #expect(calc.invariantHolds == false)
}

@Test func windowHeightMatchHonoredAsValid() {
  #expect(makeCalc().invariantHolds == true)
}

@Test func targetOriginIsAlwaysIntegerForAllPositionsAndScreens() {
  // Image-fidelity guard: every emitted target origin must have integer
  // x and y so the banner renders crisp at any DPI.
  let screens: [ScreenInfo] = [
    ScreenInfo(
      frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
      visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055), isPrimary: true),
    ScreenInfo(
      frame: CGRect(x: 0, y: 0, width: 1366, height: 768),
      visibleFrame: CGRect(x: 0, y: 25, width: 1366, height: 670), isPrimary: true),
    ScreenInfo(
      frame: CGRect(x: 0, y: 0, width: 2560, height: 1600),
      visibleFrame: CGRect(x: 0, y: 25, width: 2560, height: 1497), isPrimary: true),
  ]
  let banners: [CGRect] = [
    CGRect(x: 1544, y: 0, width: 360, height: 80),
    CGRect(x: 1545, y: 1, width: 361, height: 81),
    CGRect(x: 990, y: 7, width: 355, height: 79),
  ]
  for screen in screens {
    let window = CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
    for banner in banners {
      let calc = PositionCalculator(
        windowFrame: window, bannerFrame: banner, screen: screen,
        primaryHeight: screen.frame.height)
      for position in Position.allCases {
        let origin = calc.targetOrigin(for: position)
        let context =
          "\(position.rawValue) on \(screen.frame.size) with banner \(banner.size)"
        #expect(origin.x == origin.x.rounded(), "non-integer x for \(context)")
        #expect(origin.y == origin.y.rounded(), "non-integer y for \(context)")
      }
    }
  }
}

@Test func middleLeftAndMiddleRightCenterVertically() {
  // .middleLeft / .middleRight share the y math with .middle (vertical
  // = .middle), so y must equal middle's y. x must match topLeft for
  // middleLeft and topRight for middleRight.
  let calc = makeCalc()
  let middleY = calc.targetOrigin(for: .middle).y
  let left = calc.targetOrigin(for: .middleLeft)
  let right = calc.targetOrigin(for: .middleRight)
  #expect(left.x == calc.targetOrigin(for: .topLeft).x)
  #expect(left.y == middleY)
  #expect(right.x == calc.targetOrigin(for: .topRight).x)
  #expect(right.y == middleY)
}

@Test func bottomLeftAndBottomMiddleShareBottomY() {
  // .bottomLeft / .bottomMiddle share the y math with .bottomRight.
  let calc = makeCalc()
  let bottomY = calc.targetOrigin(for: .bottomRight).y
  let bottomLeft = calc.targetOrigin(for: .bottomLeft)
  let bottomMiddle = calc.targetOrigin(for: .bottomMiddle)
  #expect(bottomLeft.x == calc.targetOrigin(for: .topLeft).x)
  #expect(bottomLeft.y == bottomY)
  #expect(bottomMiddle.x == calc.targetOrigin(for: .topMiddle).x)
  #expect(bottomMiddle.y == bottomY)
}

@Test func degenerateVisibleFrameFailsInvariant() {
  // A degenerate (zero-height) visible frame can occur transiently
  // during display reconfiguration. The calculator must refuse to
  // produce coordinates from such a snapshot.
  let degenerate = ScreenInfo(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 0),
    isPrimary: true
  )
  let calc = makeCalc(screen: degenerate)
  #expect(calc.invariantHolds == false)
}

@Test func invariantAbsorbsSubPixelFloatNoise() {
  // AX and NSScreen heights flow through different conversions and can
  // diverge by floating-point noise smaller than a logical pixel. The
  // invariant tolerates such drift; only structural mismatches abort.
  let driftScreen = ScreenInfo(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080.0001),
    visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),
    isPrimary: true
  )
  let calc = makeCalc(screen: driftScreen)
  #expect(calc.invariantHolds == true)
}

@Test func restingBannerFrameAnchorsToRightInsetOnPrimary() {
  // Primary display: container window AX origin is (0, 0), so the only
  // adjustment is the x anchor to the fixed right inset. A 360-wide banner
  // in a 1920-wide window rests at x = 1920 - 360 - 16 = 1544; y passes
  // through unchanged because the window origin y is 0.
  let window = CGRect(x: 0, y: 0, width: 1920, height: 1080)
  let live = CGRect(x: 1920, y: 12, width: 360, height: 80)  // minX off-screen mid-slide
  let resting = PositionCalculator.restingBannerFrame(windowFrame: window, liveBannerFrame: live)
  #expect(resting.minX == 1544)
  #expect(resting.minY == 12)
  #expect(resting.width == 360)
  #expect(resting.height == 80)
}

@Test func restingBannerFrameRebasesYOnDisplayAbovePrimary() {
  // Regression for the screen-space-Y bug: a display positioned ABOVE the
  // primary has a container window whose AX origin y is negative (its top
  // edge is above the primary's top in AX's top-left-origin space). The
  // banner's live AX minY is likewise negative. Window-relative y must be
  // the difference, landing back in 0...windowHeight — otherwise the
  // negative screen-space y leaks through and `invariantHolds` (minY >= 0)
  // rejects the valid layout, so the banner is never repositioned.
  let window = CGRect(x: 0, y: -768, width: 1366, height: 768)
  let live = CGRect(x: 1366, y: -756, width: 360, height: 80)  // 12pt below the window top
  let resting = PositionCalculator.restingBannerFrame(windowFrame: window, liveBannerFrame: live)
  #expect(resting.minY == 12, "y must be rebased to window-relative (live.minY - window.origin.y)")
  let expectedX: CGFloat = 1366 - 360 - 16  // window width - banner width - right inset
  #expect(resting.minX == expectedX)
  // The rebased frame must satisfy the invariant the calculator enforces.
  let calc = PositionCalculator(
    windowFrame: window, bannerFrame: resting,
    screen: ScreenInfo(
      frame: CGRect(x: 0, y: 1080, width: 1366, height: 768),
      visibleFrame: CGRect(x: 0, y: 1080, width: 1366, height: 768), isPrimary: false),
    primaryHeight: 1080)
  #expect(calc.invariantHolds == true, "rebased banner frame must satisfy invariantHolds")
}

@Test func multiMonitorUsesPrimaryHeightAsAXFlipPivot() {
  // Multi-monitor AX flip invariant: AX coordinates flip the y axis
  // around the *primary* display's height, not the screen the window
  // belongs to. Primary 1920x1080 at AppKit (0, 0). Secondary 1366x768
  // positioned ABOVE the primary at AppKit (0, 1080). The secondary's
  // notification UI window sits at AX (0, -768), negative because
  // secondary's top edge is above the primary's top in AX coords.
  let primary = ScreenInfo(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),
    isPrimary: true)
  let secondary = ScreenInfo(
    frame: CGRect(x: 0, y: 1080, width: 1366, height: 768),
    visibleFrame: CGRect(x: 0, y: 1080, width: 1366, height: 768),  // no menu bar/dock
    isPrimary: false)
  let secondaryWindow = CGRect(x: 0, y: -768, width: 1366, height: 768)
  let banner = CGRect(x: 990, y: 0, width: 360, height: 80)

  let calc = PositionCalculator(
    windowFrame: secondaryWindow,
    bannerFrame: banner,
    screen: secondary,
    primaryHeight: primary.frame.height
  )

  // .bottomRight on the secondary:
  //   visibleTopAX    = 1080 - (1080 + 768) = -768
  //   visibleBottomAX = 1080 - 1080         = 0
  //   targetBannerBottomAX = 0 - dockPadding(30) = -30
  //   bannerBottomInWindow = 0 + 80              = 80
  //   window y = -30 - 80 = -110
  let origin = calc.targetOrigin(for: .bottomRight)
  #expect(origin.x == 0, "with .right column the AX window x is unchanged")
  #expect(
    origin.y == -110,
    "bottom edge on the secondary must use the PRIMARY's height as the AX flip pivot")
}
