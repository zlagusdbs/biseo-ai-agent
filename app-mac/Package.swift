// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KimBiseo",
    platforms: [.macOS(.v15)],
    targets: [
        // 화면과 무관한 로직. 아래 Checks 실행 타깃으로 검증한다 (Xcode 없이 XCTest 를 쓸 수 없어서).
        .target(name: "KimBiseoCore"),
        .executableTarget(name: "KimBiseo", dependencies: ["KimBiseoCore"]),
        .executableTarget(name: "KimBiseoCoreChecks", dependencies: ["KimBiseoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
