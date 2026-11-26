import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the uae_pass_kit example's original icon (a shield with a check
// mark) in the variants flutter_launcher_icons needs.
let size = 1024
let brand = CGColor(srgbRed: 0x00/255, green: 0x89/255, blue: 0x7B/255, alpha: 1)  // teal
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
let outDir = CommandLine.arguments[1]

/// Shield path with its centre at (512, 512), scaled by `scale` (1 = 640px tall).
func shield(_ scale: CGFloat) -> CGPath {
  let p = CGMutablePath()
  let w: CGFloat = 520 * scale, h: CGFloat = 640 * scale
  let cx: CGFloat = 512, top = 512 + h / 2, bottom = 512 - h / 2
  p.move(to: CGPoint(x: cx, y: top))
  p.addCurve(to: CGPoint(x: cx + w / 2, y: top - h * 0.14),
             control1: CGPoint(x: cx + w * 0.18, y: top - h * 0.06),
             control2: CGPoint(x: cx + w * 0.36, y: top - h * 0.12))
  p.addLine(to: CGPoint(x: cx + w / 2, y: 512 + h * 0.02))
  p.addCurve(to: CGPoint(x: cx, y: bottom),
             control1: CGPoint(x: cx + w / 2, y: 512 - h * 0.28),
             control2: CGPoint(x: cx + w * 0.22, y: bottom + h * 0.1))
  p.addCurve(to: CGPoint(x: cx - w / 2, y: 512 + h * 0.02),
             control1: CGPoint(x: cx - w * 0.22, y: bottom + h * 0.1),
             control2: CGPoint(x: cx - w / 2, y: 512 - h * 0.28))
  p.addLine(to: CGPoint(x: cx - w / 2, y: top - h * 0.14))
  p.addCurve(to: CGPoint(x: cx, y: top),
             control1: CGPoint(x: cx - w * 0.36, y: top - h * 0.12),
             control2: CGPoint(x: cx - w * 0.18, y: top - h * 0.06))
  p.closeSubpath()
  return p
}

func check(_ scale: CGFloat) -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 512 - 120 * scale, y: 512 + 10 * scale))
  p.addLine(to: CGPoint(x: 512 - 30 * scale, y: 512 - 80 * scale))
  p.addLine(to: CGPoint(x: 512 + 140 * scale, y: 512 + 110 * scale))
  return p
}

enum Check { case color(CGColor), cutOut }

func render(_ name: String, background: CGColor?, shieldColor: CGColor,
            check checkStyle: Check, scale: CGFloat) {
  let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  if let background {
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
  }
  ctx.addPath(shield(scale))
  ctx.setFillColor(shieldColor)
  ctx.fillPath()

  ctx.addPath(check(scale))
  ctx.setLineWidth(70 * scale)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  switch checkStyle {
  case .color(let c):
    ctx.setStrokeColor(c)
  case .cutOut:
    ctx.setBlendMode(.clear)
  }
  ctx.strokePath()

  let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
  CGImageDestinationFinalize(dest)
}

// Full-bleed icon (iOS light, legacy Android, web).
render("icon.png", background: brand, shieldColor: white, check: .color(brand), scale: 1)
// Android adaptive foreground: inside the 66% safe zone, on transparent.
render("icon_foreground.png", background: nil, shieldColor: white, check: .color(brand), scale: 1)
// Android 13+ themed (monochrome) icon.
render("icon_monochrome.png", background: nil, shieldColor: white, check: .cutOut, scale: 1)
// iOS 18 dark: transparent background, the system draws the dark backdrop.
render("icon_dark.png", background: nil, shieldColor: brand, check: .cutOut, scale: 1)
// iOS 18 tinted: grayscale on black.
render("icon_tinted.png", background: black, shieldColor: white, check: .color(black), scale: 1)
