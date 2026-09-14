import AppKit
import SwiftUI
import XCTest
@testable import MarkNote

/// 采集需求表单：各分区渲染成图（肉眼看排版 + 防布局回归）
final class CollectorFormTests: XCTestCase {

    @MainActor
    private func render(_ view: some View, to path: String) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.4
        let image = try XCTUnwrap(renderer.nsImage, "应能出图")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5000, "内容不该是空白")
        try? png.write(to: URL(fileURLWithPath: path))
        return rep
    }

    /// 图片需求：基本 / 风格 / 画面 / 图片专属 / 来源 / 入库 / 搜索词
    @MainActor
    func testRenderImageForm() throws {
        let (store, _) = try TestEnv.makeStore()
        var r = CollectRequest()
        r.kind = "image"
        r.subject = "赛博朋克霓虹街道"
        r.usage = "笔记封面"
        r.styles = ["赛博朋克", "电影感"]
        r.tones = ["冷色", "高对比"]
        r.palette = ["蓝", "粉"]
        r.orientation = CollectOrientation.landscape.rawValue
        r.minSize = CollectMinSize.uhd2160.rawValue
        r.imageType = CollectImageType.photo.rawValue
        r.license = CollectLicense.commercial.rawValue
        r.recency = CollectRecency.month.rawValue
        r.count = 12
        let view = CollectorView(initialStage: .review, request: r)
        let sections = VStack(alignment: .leading, spacing: 16) {
            CollectorView(initialStage: .review, request: r).basicsSection
            CollectorView(initialStage: .review, request: r).styleSection
            CollectorView(initialStage: .review, request: r).visualSection
            CollectorView(initialStage: .review, request: r).imageSection
            CollectorView(initialStage: .review, request: r).sourceSection
            CollectorView(initialStage: .review, request: r).archiveSection
            CollectorView(initialStage: .review, request: r).queryPreview
        }
        .padding(18)
        .frame(width: 780)
        .background(Color(nsColor: appAppearance.editorBackground))
        .environment(store)
        _ = view
        _ = try render(sections, to: "/tmp/marknote-collector-form.png")
    }

    /// 视频需求：出现视频专属分区（时长/清晰度/声音/字幕/平台）
    @MainActor
    func testVideoFormHasVideoSection() throws {
        let (store, _) = try TestEnv.makeStore()
        var r = CollectRequest()
        r.kind = "video"
        r.subject = "城市夜景延时"
        r.videoDuration = CollectVideoDuration.short.rawValue
        r.videoResolution = CollectVideoResolution.fhd.rawValue
        r.videoAudio = CollectVideoAudio.with.rawValue
        r.videoSubtitle = CollectVideoSubtitle.without.rawValue
        r.platforms = ["哔哩哔哩", "抖音"]
        let view = CollectorView(initialStage: .review, request: r)
        let sections = VStack(alignment: .leading, spacing: 16) {
            CollectorView(initialStage: .review, request: r).videoSection
            CollectorView(initialStage: .review, request: r).queryPreview
        }
        .padding(18)
        .frame(width: 780)
        .background(Color(nsColor: appAppearance.editorBackground))
        .environment(store)
        _ = view
        _ = try render(sections, to: "/tmp/marknote-collector-video-form.png")
    }

    /// AI 追问页：问题 + 可点选项 + 自由补充（排版肉眼过一遍）
    @MainActor
    func testRenderClarifyStage() throws {
        let (store, _) = try TestEnv.makeStore()
        var r = CollectRequest()
        r.kind = "image"
        r.subject = "赛博朋克"
        let questions = [
            CollectClarifyQuestion(id: "q1", question: "要几张、横图还是竖图？", field: "count",
                                   options: ["3 张横图", "6 张横图", "3 张竖图"]),
            CollectClarifyQuestion(id: "q2", question: "用在哪儿？（影响构图留白）", field: "usage",
                                   options: ["笔记封面", "文章配图", "视频封面"]),
        ]
        // 只渲染内容区：ImageRenderer 画不了 ScrollView 内部（完整页会是一片空白）
        let body = CollectorView(initialStage: .clarify, request: r, clarifyQuestions: questions)
            .clarifyBody
            .frame(width: 780)
            .background(Color(nsColor: appAppearance.editorBackground))
            .environment(store)
        _ = try render(body, to: "/tmp/marknote-collector-clarify.png")
    }

    /// 站点账号面板：登录态一览 + 登录/退出入口
    @MainActor
    func testRenderAccountsSheet() throws {
        let (store, _) = try TestEnv.makeStore()
        // 只渲染清单（ImageRenderer 画不了 ScrollView 内部，完整面板会是空白）
        let view = CollectorAccountsSheet()
            .sitesList
            .frame(width: 560)
            .background(Color(nsColor: appAppearance.editorBackground))
            .environment(store)
        _ = try render(view, to: "/tmp/marknote-collector-accounts.png")
    }
}
