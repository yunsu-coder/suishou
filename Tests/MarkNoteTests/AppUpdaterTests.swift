import XCTest
@testable import MarkNote

final class AppUpdaterTests: XCTestCase {

    func testNeedsUpdateLogic() {
        XCTAssertFalse(AppUpdater.needsUpdate(buildSHA: "abc1234", repoHead: "abc1234", repoDirty: false),
                       "同提交且干净 → 已是最新")
        XCTAssertTrue(AppUpdater.needsUpdate(buildSHA: "abc1234", repoHead: "def5678", repoDirty: false),
                      "提交变了 → 有更新")
        XCTAssertTrue(AppUpdater.needsUpdate(buildSHA: "abc1234", repoHead: "abc1234", repoDirty: true),
                      "工作树有未提交改动 → 也算有更新")
    }

    func testUpdateScriptMentionsRepoAndBuildScript() {
        let script = AppUpdater.updateScriptText(repo: URL(fileURLWithPath: "/tmp/demo-repo"),
                                                 appPath: "/Applications/随手.app")
        XCTAssertTrue(script.contains("cd \"/tmp/demo-repo\""))
        XCTAssertTrue(script.contains("./scripts/build-app.sh"))
        XCTAssertTrue(script.contains("open \"/Applications/随手.app\""))
    }
}
