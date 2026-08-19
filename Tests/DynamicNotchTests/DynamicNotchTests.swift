import XCTest
@testable import DynamicNotch

final class DynamicNotchTests: XCTestCase {
    func testConfigurationNormalizesDimensionsAndRadius() {
        let configuration = DynamicNotchConfiguration(
            direction: .left,
            width: -20,
            height: 80,
            cornerRadius: 100
        )

        XCTAssertEqual(configuration.width, 1)
        XCTAssertEqual(configuration.height, 80)
        XCTAssertEqual(configuration.cornerRadius, 0.5)
    }

    func testAttachedEdgeRailFollowsTheAttachedDirection() {
        XCTAssertEqual(
            DynamicNotchConfiguration(direction: .top, width: 200, height: 80)
                .attachedEdgeRail,
            3
        )
        XCTAssertEqual(
            DynamicNotchConfiguration(direction: .bottom, width: 200, height: 80)
                .attachedEdgeRail,
            3
        )
        XCTAssertEqual(
            DynamicNotchConfiguration(direction: .left, width: 80, height: 200)
                .attachedEdgeRail,
            0
        )
        XCTAssertEqual(
            DynamicNotchConfiguration(
                direction: .top,
                width: 200,
                height: 80,
                attachedEdgeRail: 18
            ).attachedEdgeRail,
            18
        )
    }

    func testTopAndBottomContentUseOnlyTheAttachedEdgeRailVertically() {
        let topConfiguration = DynamicNotchConfiguration(
            direction: .top,
            width: 360,
            height: 56,
            cornerRadius: 20,
            shoulderRadius: 14,
            attachedEdgeRail: 24
        )
        let bottomConfiguration = DynamicNotchConfiguration(
            direction: .bottom,
            width: 360,
            height: 56,
            cornerRadius: 20,
            shoulderRadius: 14,
            attachedEdgeRail: 3
        )

        let topInsets = DynamicNotchContentGeometry.curveSafeInsets(
            for: topConfiguration
        )
        let bottomInsets = DynamicNotchContentGeometry.curveSafeInsets(
            for: bottomConfiguration
        )

        XCTAssertEqual(topInsets.top, 0)
        XCTAssertEqual(topInsets.bottom, 0)
        XCTAssertEqual(bottomInsets.top, 0)
        XCTAssertEqual(bottomInsets.bottom, 0)
        XCTAssertEqual(topInsets.leading, 34)
        XCTAssertEqual(bottomInsets.trailing, 34)
    }

    func testAutomaticAttachedRailUsesTheScreenSafeArea() {
        let safeArea = NSEdgeInsets(top: 24, left: 0, bottom: 8, right: 0)

        XCTAssertEqual(
            DynamicNotchSafeAreaResolver.attachedEdgeRail(
                for: .top,
                override: nil,
                safeAreaInsets: safeArea
            ),
            24
        )
        XCTAssertEqual(
            DynamicNotchSafeAreaResolver.attachedEdgeRail(
                for: .bottom,
                override: nil,
                safeAreaInsets: safeArea
            ),
            8
        )
        XCTAssertEqual(
            DynamicNotchSafeAreaResolver.attachedEdgeRail(
                for: .top,
                override: 0,
                safeAreaInsets: safeArea
            ),
            0
        )
    }

    func testCompactMetricsUseTheStatusBarAndPhysicalCameraGap() {
        let safeArea = NSEdgeInsets(top: 24, left: 0, bottom: 0, right: 0)
        let leftArea = CGRect(x: 0, y: 876, width: 650, height: 24)
        let rightArea = CGRect(x: 790, y: 876, width: 650, height: 24)

        XCTAssertEqual(
            DynamicNotchSafeAreaResolver.compactHeight(
                override: nil,
                statusBarThickness: 22,
                safeAreaInsets: safeArea
            ),
            24
        )
        XCTAssertEqual(
            DynamicNotchSafeAreaResolver.compactCenterGap(
                override: nil,
                auxiliaryTopLeftArea: leftArea,
                auxiliaryTopRightArea: rightArea
            ),
            140
        )
        XCTAssertEqual(
            DynamicNotchSafeAreaResolver.compactCenterGap(
                override: 80,
                auxiliaryTopLeftArea: leftArea,
                auxiliaryTopRightArea: rightArea
            ),
            80
        )
    }

    func testPlacementAlignsAndOffsetsAlongTheAttachedEdge() {
        let configuration = DynamicNotchConfiguration(
            direction: .top,
            width: 200,
            height: 80
        )
        let screen = CGRect(x: 100, y: 50, width: 1_000, height: 700)

        let startFrame = DynamicNotchWindowGeometry.frame(
            for: configuration,
            placement: .edge(.top, alignment: .start, offset: 20),
            in: screen
        )
        let centerFrame = DynamicNotchWindowGeometry.frame(
            for: configuration,
            placement: .edge(.top, alignment: .center, offset: 0),
            in: screen
        )
        let endFrame = DynamicNotchWindowGeometry.frame(
            for: configuration,
            placement: .edge(.top, alignment: .end, offset: -30),
            in: screen
        )

        XCTAssertEqual(startFrame.origin, CGPoint(x: 120, y: 670))
        XCTAssertEqual(centerFrame.origin, CGPoint(x: 500, y: 670))
        XCTAssertEqual(endFrame.origin, CGPoint(x: 870, y: 670))
    }

    func testTopShapeHasAnAttachedLipAndCurvedShoulders() {
        let path = DynamicNotchShape(direction: .top, cornerRadius: 20)
            .path(in: CGRect(x: 0, y: 0, width: 100, height: 60))

        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 0)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 59)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 10)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 59)))
    }

    func testBottomShapeHasAnAttachedLipAndCurvedShoulders() {
        let path = DynamicNotchShape(direction: .bottom, cornerRadius: 20)
            .path(in: CGRect(x: 0, y: 0, width: 100, height: 60))

        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 59.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 1)))
    }

    func testSideShapesRoundOnlyTheExposedEdge() {
        let leftPath = DynamicNotchShape(direction: .left, cornerRadius: 20)
            .path(in: CGRect(x: 0, y: 0, width: 100, height: 60))
        let rightPath = DynamicNotchShape(direction: .right, cornerRadius: 20)
            .path(in: CGRect(x: 0, y: 0, width: 100, height: 60))

        XCTAssertTrue(leftPath.contains(CGPoint(x: 0.5, y: 30)))
        XCTAssertFalse(leftPath.contains(CGPoint(x: 10, y: 1)))
        XCTAssertTrue(rightPath.contains(CGPoint(x: 99.5, y: 30)))
        XCTAssertFalse(rightPath.contains(CGPoint(x: 90, y: 1)))
    }
}
