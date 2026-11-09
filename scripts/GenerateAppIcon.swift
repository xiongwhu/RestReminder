// SPDX-License-Identifier: CPAL-1.0
//
// EXHIBIT A. Common Public Attribution License Version 1.0.
//
// The contents of this file are subject to the Common Public Attribution License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at https://opensource.org/license/cpal-1-0. The License is based on the Mozilla Public License Version 1.1 but Sections 14 and 15 have been added to cover use of software over a computer network and provide for limited attribution for the Original Developer. In addition, Exhibit A has been modified to be consistent with Exhibit B.
//
// Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.
//
// The Original Code is RestReminder (歇一会儿), including the original source code, tests and build scripts distributed in this repository. Third-party photographs identified in Resources/PHOTO-CREDITS.md are excluded and remain subject to their original licenses.
// The Initial Developer of the Original Code is 广州迈润网络科技有限公司 (迈润智人 RaCIO).
// The Original Developer is the Initial Developer.
// All portions of the code written by the Initial Developer are Copyright (c) 2026 广州迈润网络科技有限公司. All Rights Reserved.
// Contributor(s): see individual source notices and project history.
// No alternative license is designated for the Original Code.
//
// [NOTE: The text of this Exhibit A may differ slightly from the text of the notices in the Source Code files of the Original Code. You should use the text of this Exhibit A rather than the text found in the Original Code Source Code for Your Modifications.]
//
// For Exhibit B Attribution Information, see the root LICENSE file.

import AppKit

// Original vector artwork: warm sunlight and a growing leaf. No external image assets.
func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                            xRadius: 194, yRadius: 194)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.12, alpha: 0.16)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.86, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.83, alpha: 1),
               ending: NSColor(calibratedRed: 0.81, green: 0.91, blue: 0.81, alpha: 1))!
        .draw(in: tile, angle: -65)

    let sunCenter = NSPoint(x: 388, y: 658)
    NSGraphicsContext.saveGraphicsState()
    let sunGlow = NSShadow()
    sunGlow.shadowColor = NSColor(calibratedRed: 1, green: 0.69, blue: 0.20, alpha: 0.15)
    sunGlow.shadowBlurRadius = 36
    sunGlow.shadowOffset = .zero
    sunGlow.set()
    let sun = NSBezierPath(ovalIn: NSRect(x: sunCenter.x - 126, y: sunCenter.y - 126, width: 252, height: 252))
    NSColor(calibratedRed: 0.99, green: 0.69, blue: 0.22, alpha: 1).setFill()
    sun.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 1, green: 0.78, blue: 0.32, alpha: 1),
               ending: NSColor(calibratedRed: 0.97, green: 0.54, blue: 0.16, alpha: 1))!
        .draw(in: sun, angle: -70)
    NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.22, alpha: 1).setStroke()
    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4
        let ray = NSBezierPath()
        ray.lineWidth = 20
        ray.lineCapStyle = .round
        ray.move(to: NSPoint(x: sunCenter.x + cos(angle) * 166, y: sunCenter.y + sin(angle) * 166))
        ray.line(to: NSPoint(x: sunCenter.x + cos(angle) * 191, y: sunCenter.y + sin(angle) * 191))
        ray.stroke()
    }

    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: 405, y: 348))
    leaf.curve(to: NSPoint(x: 791, y: 657),
               controlPoint1: NSPoint(x: 403, y: 619), controlPoint2: NSPoint(x: 672, y: 720))
    leaf.curve(to: NSPoint(x: 405, y: 348),
               controlPoint1: NSPoint(x: 835, y: 399), controlPoint2: NSPoint(x: 587, y: 291))
    leaf.close()
    NSGraphicsContext.saveGraphicsState()
    let leafShadow = NSShadow()
    leafShadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.15, alpha: 0.16)
    leafShadow.shadowBlurRadius = 24
    leafShadow.shadowOffset = NSSize(width: 0, height: -9)
    leafShadow.set()
    NSColor(calibratedRed: 0.19, green: 0.44, blue: 0.25, alpha: 1).setFill()
    leaf.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.35, green: 0.60, blue: 0.34, alpha: 1),
               ending: NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.22, alpha: 1))!
        .draw(in: leaf, angle: -65)

    let stem = NSBezierPath()
    stem.lineWidth = 22
    stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: 299, y: 242))
    stem.curve(to: NSPoint(x: 429, y: 376),
               controlPoint1: NSPoint(x: 328, y: 290), controlPoint2: NSPoint(x: 371, y: 330))
    NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.24, alpha: 1).setStroke()
    stem.stroke()
    let vein = NSBezierPath()
    vein.lineWidth = 13
    vein.lineCapStyle = .round
    vein.move(to: NSPoint(x: 432, y: 376))
    vein.curve(to: NSPoint(x: 733, y: 609),
               controlPoint1: NSPoint(x: 517, y: 438), controlPoint2: NSPoint(x: 630, y: 533))
    NSColor(calibratedRed: 0.87, green: 0.94, blue: 0.76, alpha: 0.92).setStroke()
    vein.stroke()
}

func png(size: Int, url: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try data.write(to: url, options: .atomic)
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath).standardizedFileURL
let set = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try png(size: size, url: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size: size * 2, url: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try png(size: 1024, url: root.appendingPathComponent("Resources/AppIcon.png"))
print("Generated original app icon at 16–1024 pixels")
