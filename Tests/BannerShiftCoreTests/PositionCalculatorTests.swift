import CoreGraphics
import Testing

@testable import BannerShiftCore

private let screen = ScreenInfo(
  frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
  visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),  // 25pt menu bar
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
  let origin = makeCalc().targetOrigin(for: .topRight)
  #expect(origin == .zero)
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
