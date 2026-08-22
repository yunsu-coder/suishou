#!/usr/bin/env swift
// 随手 App 图标生成器 —— 极简代码块版
// 设计：深夜蓝黑底 + 一道青→紫渐变 "</>" 代码符号（圆头笔触 + 柔光晕）
// 一句话：一个代码块。简单、直接、不解释。
// 用法: swift scripts/make-icon.swift [输出路径.png 默认 build/icon-1024.png]
import AppKit

let SIZE: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon-1024.png"
try? FileManager.default.createDirectory(at: URL(fileURLWithPath: "build"), withIntermediateDirectories: true)

guard let ctx = CGContext(data: nil, width: Int(SIZE), height: Int(SIZE),
                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("无法创建位图上下文\n", stderr)
    exit(1)
}
// CGBitmapContext 原生 y 向上 → 翻转为 y-向下（阴影 offset 同受此 CTM）
ctx.translateBy(x: 0, y: SIZE)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a).cgColor
}

// ═══ 背景：深夜蓝黑（对角微光） ═══
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [rgb(0.055, 0.075, 0.16),   // #0E1430
                             rgb(0.03, 0.035, 0.08)] as CFArray, // 深角
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 180), end: CGPoint(x: 920, y: 950), options: [])

// ═══ "</>" 代码符号 ═══
func strokePath(_ points: [CGPoint], width: CGFloat, join: Bool = true) {
    let p = NSBezierPath()
    p.move(to: points[0])
    for pt in points.dropFirst() { p.line(to: pt) }
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(join ? .round : .round)
    ctx.addPath(p.cgPath)
    ctx.strokePath()
}

// 光晕层（三层宽度递降的半透明笔 → 霓虹辉光；不依赖 setShadow 的玄学）
func glowStroke(_ points: [CGPoint], color: CGColor, widths: [CGFloat], alphas: [CGFloat]) {
    ctx.saveGState()
    for i in 0..<widths.count {
        ctx.setStrokeColor(color.copy(alpha: alphas[i])!)
        strokePath(points, width: widths[i])
    }
    ctx.restoreGState()
}

let glowWidths: [CGFloat] = [146, 116, 100]
let cyanGlowAlphas: [CGFloat] = [0.14, 0.26, 0.48]
let violetGlowAlphas: [CGFloat] = [0.12, 0.22, 0.44]

let cyan = rgb(0.25, 0.83, 0.96)     // 青 #40D4F5
let violet = rgb(0.66, 0.47, 1.00)   // 紫 #A97DFF

// 标准 </> 布局（几何已单测验证）：左 chevron / 居中斜杆 / 右 chevron
let leftChevron: [CGPoint] = [CGPoint(x: 190, y: 330), CGPoint(x: 352, y: 512), CGPoint(x: 190, y: 694)]
let slash: [CGPoint] = [CGPoint(x: 470, y: 726), CGPoint(x: 562, y: 298)]
let rightChevron: [CGPoint] = [CGPoint(x: 654, y: 330), CGPoint(x: 834, y: 512), CGPoint(x: 654, y: 694)]

// 霓虹光晕
glowStroke(leftChevron, color: cyan, widths: glowWidths, alphas: cyanGlowAlphas)
glowStroke(slash, color: violet, widths: glowWidths, alphas: violetGlowAlphas)
glowStroke(rightChevron, color: violet, widths: glowWidths, alphas: violetGlowAlphas)

// 主体：青→紫对角渐变笔触（笔锋统一圆头，简单有力）
ctx.saveGState()
ctx.setLineWidth(88)   // 主体略窄于最内层光晕，边缘干净
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
var allPaths = NSBezierPath()
func addChevron(_ pts: [CGPoint]) {
    let p = NSBezierPath()
    p.move(to: pts[0])
    for pt in pts.dropFirst() { p.line(to: pt) }
    allPaths.append(p)
}
addChevron(leftChevron)
let slashPath = NSBezierPath()
slashPath.move(to: slash[0])
slashPath.line(to: slash[1])
allPaths.append(slashPath)
addChevron(rightChevron)
ctx.addPath(allPaths.cgPath)
ctx.replacePathWithStrokedPath()
ctx.clip()
let ink = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                     colors: [cyan, rgb(0.45, 0.72, 1.0), violet] as CFArray,
                     locations: [0, 0.5, 1])!
ctx.drawLinearGradient(ink, start: CGPoint(x: 240, y: 250), end: CGPoint(x: 800, y: 780), options: [])
ctx.restoreGState()

// 主体白色内高光（每笔上沿一条细亮线，透亮但不过）
let hi = NSBezierPath()
hi.move(to: CGPoint(x: 208, y: 372))
for pt in [(CGPoint(x: 348, y: 520)), (CGPoint(x: 208, y: 652))] { hi.line(to: pt) }
hi.move(to: CGPoint(x: 488, y: 712))
hi.line(to: CGPoint(x: 566, y: 350))
hi.move(to: CGPoint(x: 676, y: 372))
for pt in [(CGPoint(x: 812, y: 520)), (CGPoint(x: 676, y: 652))] { hi.line(to: pt) }
ctx.saveGState()
ctx.setLineWidth(15)
ctx.setLineCap(.round)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
ctx.addPath(hi.cgPath)
ctx.strokePath()
ctx.restoreGState()

guard let img = ctx.makeImage() else {
    fputs("位图合成失败\n", stderr)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("PNG 编码失败\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: out))
print("图标已生成: \(out)")
