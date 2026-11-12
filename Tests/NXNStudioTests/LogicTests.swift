import XCTest
@testable import NXNStudio

final class LogicTests: XCTestCase {
    // MARK: Update versions

    func testVersionComparison() {
        XCTAssertEqual(UpdateService.compare("1.2.0", "1.1.0"), 1)
        XCTAssertEqual(UpdateService.compare("1.10.0", "1.9.9"), 1)
        XCTAssertEqual(UpdateService.compare("1.0", "1.0.0"), 0)
        XCTAssertEqual(UpdateService.compare("2.0", "2.0.1"), -1)
    }

    // MARK: Package selection

    func testPackageClassification() {
        let base = BuildContent.titleID(in: "[Game] Mario Kart 8 Deluxe [0100152000022000][v0].nsp")
        XCTAssertEqual(base, "0100152000022000")
        XCTAssertEqual(BuildContent.versionToken(in: "[Game] X [0100152000022000][v1441792].nsp"), "v1441792")
        XCTAssertNil(BuildContent.versionToken(in: "mod.nsp"))
    }

    func testPackagesBesideSortsKinds() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxn-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let names = [
            "[Game] Mario Kart [0100152000022000][v0].nsp",
            "[Update] Mario Kart [0100152000022000][v1441792].nsp",
            "[DLC] Mario Kart [0100152000023001][v0].nsp",
            "random-mod.nsp",
        ]
        for name in names {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data("x".utf8))
        }

        let source = folder.appendingPathComponent(names[0])
        let packages = BuildContent.packages(beside: source, baseID: "0100152000022000")

        XCTAssertEqual(packages.count, 4)
        XCTAssertEqual(packages.first?.kind, .base)
        XCTAssertTrue(packages.contains { $0.kind == .update })
        XCTAssertTrue(packages.contains { $0.kind == .dlc })
        XCTAssertTrue(packages.contains { $0.kind == .other })
    }

    // MARK: Title matching (IGDB)

    func testTitleMatching() {
        let names = ["Mario Kart 8 Deluxe", "Mario Kart 8 Deluxe – Booster Course Pass"]
        XCTAssertEqual(TitleMatcher.normalize("Mario Kart 8 Deluxe™"), "mario kart 8 deluxe")
        XCTAssertGreaterThan(TitleMatcher.score(candidate: names[0], target: "mario kart 8 deluxe"), 0.9)
        XCTAssertLessThan(TitleMatcher.score(candidate: "Hades II", target: "Mario Kart 8 Deluxe"), 0.4)
    }

    // MARK: Commit classification

    func testCommitKinds() {
        XCTAssertEqual(RepoChangelog.kind(for: "fix: keep the HUD"), .fix)
        XCTAssertEqual(RepoChangelog.kind(for: "A pool texture no longer draws black"), .fix)
        XCTAssertEqual(RepoChangelog.kind(for: "Hades II renders 12% faster"), .perf)
        XCTAssertEqual(RepoChangelog.kind(for: "Hades II registers its update 1.0.1"), .feature)
        XCTAssertEqual(RepoChangelog.kind(for: "The uniform copy thread hands off"), .other)
    }

    // MARK: Environment

    func testHomebrewComesFirstInPath() {
        let path = ShellRunner.environment()["PATH"] ?? ""
        let entries = path.split(separator: ":").map(String.init)
        guard let brew = entries.firstIndex(of: "/opt/homebrew/bin"),
              let system = entries.firstIndex(of: "/usr/bin") else {
            return XCTFail("PATH incomplet : \(path)")
        }
        XCTAssertLessThan(brew, system, "Homebrew doit précéder /usr/bin")
    }

    // MARK: Checkout detection

    func testRepoInspection() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxn-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("dm/games"), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("scripts/build_ipa_from_nsp.py").path,
            contents: Data("print('x')".utf8))

        let status = RepoInspector.inspect(folder)
        XCTAssertTrue(status.isValid, status.message)

        let missing = RepoInspector.inspect(folder.appendingPathComponent("absent"))
        XCTAssertFalse(missing.isValid)
    }

    // MARK: Build arguments

    func testBuildArgumentsCarryFlags() {
        var options = BuildOptions()
        options.platform = .macApp
        options.keepExtracted = true
        options.romfsSeparate = true
        options.packageVersion = "v1441792"

        let args = options.arguments()
        XCTAssertTrue(args.contains("--platform"))
        XCTAssertTrue(args.contains("mac-app"))
        XCTAssertTrue(args.contains("--romfs"))
        XCTAssertTrue(args.contains("--keep-extracted"))
        XCTAssertTrue(args.contains("v1441792"))
    }
}
