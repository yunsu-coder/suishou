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
}
