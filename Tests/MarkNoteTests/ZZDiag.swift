import XCTest
@testable import MarkNote

final class ZZDiagTests: XCTestCase {
    @MainActor
    func testDiagnoseInstalledPlugins() {
        let pm = PluginManager.shared
        pm.scan(workspaceDir: nil)
        print("DIAG-VIEWS:")
        for v in pm.allViews() {
            print("DIAG-VIEW: type=\(v.type.rawValue) placement=\(v.placement.rawValue) name=\(v.name) dir=\(v.dir)")
        }
        print("DIAG-ISSUE-flowchart: \(pm.viewIssues(for: "view-flowchart"))")
        print("DIAG-ISSUE-collector: \(pm.viewIssues(for: "view-collector"))")
        let pkgs = pm.allPackages().map { "\($0.id)(\($0.kind.rawValue),enabled=\($0.enabled))" }
        print("DIAG-PACKAGES: \(pkgs)")
    }
}
