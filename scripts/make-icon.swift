#!/usr/bin/env swift
// 随手 App 图标生成器 —— 亮色朴素版
// 设计:浅灰白圆角底 + 深墨色笔记本 + 深灰三条线(Apple Notes 式简洁)
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
ctx.translateBy(x: 0, y: SIZE)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a).cgColor
}

// ═══ 背景:浅灰白圆角(暖白),近纯色 ═══
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [rgb(0.94, 0.95, 0.96),   // #F0F2F5 浅灰白
                             rgb(0.85, 0.87, 0.90)] as CFArray,  // #D9DDE6
                    locations: [0, 1])!
let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: SIZE, height: SIZE),
                          xRadius: SIZE * 0.2237, yRadius: SIZE * 0.2237)
ctx.saveGState()
ctx.addPath(bgPath.cgPath)
ctx.clip()
ctx.drawLinearGradient(bg, start: CGPoint(x: 120, y: 0), end: CGPoint(x: 900, y: SIZE), options: [])
ctx.restoreGState()

// ═══ 主体:深墨色笔记本(白纸反转为深板) + 右上折角 ═══
let doc = NSBezierPath(roundedRect: NSRect(x: 292, y: 210, width: 440, height: 570),
                       xRadius: 46, yRadius: 46)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 36,
               color: NSColor.black.withAlphaComponent(0.16).cgColor)
ctx.addPath(doc.cgPath)
ctx.setFillColor(NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.24, alpha: 1).cgColor)  // #2B303D
ctx.fillPath()
ctx.restoreGState()

// 折角:右上
let fold = NSBezierPath()
fold.move(to: CGPoint(x: 732, y: 780))
fold.line(to: CGPoint(x: 582, y: 780))
fold.line(to: CGPoint(x: 732, y: 630))
fold.close()
ctx.saveGState()
ctx.addPath(fold.cgPath)
ctx.clip()
ctx.setFillColor(NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.38, alpha: 1).cgColor)  // 折角略亮
ctx.fill(NSRect(x: 540, y: 580, width: 260, height: 260))
ctx.restoreGState()

// 折角弧线
let foldCurve = NSBezierPath()
foldCurve.move(to: CGPoint(x: 582, y: 780))
foldCurve.curve(to: CGPoint(x: 732, y: 630),
                controlPoint1: CGPoint(x: 732 - 36, y: 780 - 36),
                controlPoint2: CGPoint(x: 732 - 36, y: 780 - 36))
ctx.saveGState()
ctx.setLineWidth(9)
ctx.setStrokeColor(NSColor(calibratedWhite: 0.45, alpha: 1).cgColor)
ctx.addPath(foldCurve.cgPath)
ctx.strokePath()
ctx.restoreGState()

// ═══ 三条文本线:纯白灰(深板上亮线) ═══
func line(_ y: CGFloat, _ w: CGFloat) {
    let p = NSBezierPath(roundedRect: NSRect(x: 356, y: y, width: w, height: 38),
                         xRadius: 19, yRadius: 19)
    ctx.saveGState()
    ctx.setFillColor(NSColor(calibratedWhite: 0.82, alpha: 1).cgColor)
    ctx.addPath(p.cgPath)
    ctx.fillPath()
    ctx.restoreGState()
}
line(328, 312)
line(508, 256)
line(688, 312)

guard let img = ctx.makeImage() else { fputs("位图合成失败\n", stderr); exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { fputs("PNG 编码失败\n", stderr); exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("图标已生成: \(out)")
