import XCTest
@testable import MarkNote

/// AI 追问闭环：解析 → 审校（不够明确就追问）→ 回答并回填 → 再审 → 放行。
/// 全程用注入的假模型，不碰网络。
final class CollectorClarifyTests: XCTestCase {

    // MARK: - 审校结果解析

    func testParseReviewWithQuestions() throws {
        let reply = """
        ```json
        {"ready":false,"reason":"没说清图片方向和数量","questions":[
          {"id":"q1","question":"要横图还是竖图？","field":"orientation","options":["横图","竖图","方图"]},
          {"id":"q2","question":"要几张？","field":"count","options":["3 张","6 张"]}]}
        ```
        """
        let review = try XCTUnwrap(CollectorClarify.parseReview(reply))
        XCTAssertFalse(review.ready)
        XCTAssertEqual(review.reason, "没说清图片方向和数量")
        XCTAssertEqual(review.questions.count, 2)
        XCTAssertEqual(review.questions[0].options, ["横图", "竖图", "方图"])
        XCTAssertEqual(review.questions[0].field, "orientation")
    }

    func testParseReviewReady() throws {
        let review = try XCTUnwrap(CollectorClarify.parseReview(
            #"{"ready":true,"reason":"","questions":[]}"#))
        XCTAssertTrue(review.ready)
        XCTAssertTrue(review.questions.isEmpty)
        XCTAssertNil(review.reason, "空 reason 不该显示")
    }

    func testParseReviewToleratesSloppyModels() throws {
        // ready=true 却还给问题 → 按「没问完」处理（宁可多问一句）
        let contradictory = try XCTUnwrap(CollectorClarify.parseReview(
            #"{"ready":true,"questions":[{"question":"要几张？"}]}"#))
        XCTAssertFalse(contradictory.ready)
        XCTAssertEqual(contradictory.questions.count, 1)
        // 字符串 "false" / 缺 id / 选项超量
        let raw = """
        {"ready":"false","reason":"还不够具体","questions":[
          {"question":"平台？","options":["B站","抖音","YouTube","小红书","腾讯","快手","微博"]},
          {"question":"时长？","options":[]},
          {"question":"字数？","options":["短文"]},
          {"question":"第四个问题应被丢掉","options":[]}]}
        """
        let sloppy = try XCTUnwrap(CollectorClarify.parseReview(raw))
        XCTAssertFalse(sloppy.ready)
        XCTAssertEqual(sloppy.questions.count, CollectorClarify.maxQuestions, "最多 3 条")
        XCTAssertEqual(sloppy.questions[0].id, "q1", "缺 id 要自动补")
        XCTAssertEqual(sloppy.questions[0].options.count, 6, "选项最多 6 个")
        XCTAssertEqual(sloppy.reason, "还不够具体")
    }

    func testParseReviewGarbageReturnsNil() {
        XCTAssertNil(CollectorClarify.parseReview("模型今天不想干活"))
        XCTAssertNil(CollectorClarify.parseReview("[]"))
    }

    // MARK: - 回答拼接与轮次

    func testFollowUpTextKeepsQuestionsAndAnswers() {
        let text = CollectorClarify.followUpText("找点赛博朋克图", answers: [
            (question: "要横图还是竖图？", answer: "横图"),
            (question: "要几张？", answer: ""),
        ])
        XCTAssertTrue(text.hasPrefix("找点赛博朋克图"))
        XCTAssertTrue(text.contains("【追问补充】"))
        XCTAssertTrue(text.contains("Q：要横图还是竖图？"))
        XCTAssertTrue(text.contains("A：横图"))
        XCTAssertFalse(text.contains("要几张？"), "没回答的问题不带上")
    }

    func testFollowUpTextWithoutAnswersKeepsOriginal() {
        XCTAssertEqual(CollectorClarify.followUpText(" 原始需求 ", answers: [(question: "q", answer: " ")]),
                       "原始需求")
    }

    func testRoundLimitAllowsThreeRounds() {
        XCTAssertTrue(CollectorClarify.canAskMore(round: 0))
        XCTAssertTrue(CollectorClarify.canAskMore(round: 2))
        XCTAssertFalse(CollectorClarify.canAskMore(round: 3), "问满 3 轮就放行，不锁死用户")
        XCTAssertFalse(CollectorClarify.canAskMore(round: 9))
    }

    // MARK: - 闭环（假模型）

    func testClarifyLoopThenReady() async throws {
        // 假「解析器」：第一遍只认出主题；带追问补充后补齐方向与数量
        let intent: (String, String) async throws -> String = { _, user in
            user.contains("追问补充")
                ? #"{"kind":"image","subject":"赛博朋克霓虹街道","orientation":"landscape","count":6}"#
                : #"{"kind":"image","subject":"赛博朋克"}"#
        }
        // 假「审校员」：第 1 轮追问，第 2 轮放行
        let reviewer: (String, String) async throws -> String = { _, user in
            user.contains("第 2 轮")
                ? #"{"ready":true,"reason":"","questions":[]}"#
                : #"{"ready":false,"reason":"没说清方向和数量","questions":[{"id":"q1","question":"要几张、横竖？","field":"count","options":["3 张横图","6 张横图"]}]}"#
        }

        let parsed = await CollectorIntent.parse("找点赛博朋克图", current: CollectRequest(),
                                                 complete: intent)
        var r = try XCTUnwrap(parsed)
        XCTAssertEqual(r.subject, "赛博朋克")

        let reviewed = await CollectorClarify.review(r, userText: "找点赛博朋克图",
                                                     round: 1, complete: reviewer)
        let first = try XCTUnwrap(reviewed)
        XCTAssertFalse(first.ready)
        XCTAssertEqual(first.questions.first?.options, ["3 张横图", "6 张横图"])

        let text = CollectorClarify.followUpText("找点赛博朋克图",
                                                 answers: [(question: first.questions[0].question, answer: "6 张横图")])
        let reparsed = await CollectorIntent.parse(text, current: r, complete: intent)
        r = try XCTUnwrap(reparsed)
        XCTAssertEqual(r.count, 6, "回答要能回填到需求卡")
        XCTAssertEqual(r.orientation, "landscape")

        let reviewedAgain = await CollectorClarify.review(r, userText: text, round: 2, complete: reviewer)
        let second = try XCTUnwrap(reviewedAgain)
        XCTAssertTrue(second.ready, "问清了就该放行")
        XCTAssertTrue(r.isReady, "类型 + 主题都在 → 可以直接开工")
    }

    func testClarifyModelFailureDoesNotBlock() async {
        struct Boom: Error {}
        let failing: (String, String) async throws -> String = { _, _ in throw Boom() }
        let review = await CollectorClarify.review(CollectRequest(), userText: "随便", round: 1,
                                                   complete: failing)
        XCTAssertNil(review, "模型挂了就放行到需求卡，不能把人卡在问答里")
    }
}
