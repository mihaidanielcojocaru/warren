import AppKit

let width: CGFloat = 600, height: CGFloat = 400

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

/// The Finder positions icons from the top left, so quote those numbers and
/// convert here rather than flipping the context — a flipped context draws text
/// upside down.
func fromTop(_ y: CGFloat) -> CGFloat { height - y }

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext

    // Loam gradient, lighter at the top, the same family as the app icon.
    NSGradient(colors: [rgb(74, 87, 68), rgb(51, 61, 47), rgb(20, 26, 19)],
               atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 270)

    // A warm pool of light behind the app icon, echoing the burrow. Drawn as an
    // explicit radial so nothing clips to a rectangle.
    let centre = CGPoint(x: 150, y: fromTop(205))
    let warm = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(245, 185, 66, 0.22).cgColor,
                                   rgb(245, 185, 66, 0).cgColor] as CFArray,
                          locations: [0, 1])!
    cg.drawRadialGradient(warm, startCenter: centre, startRadius: 0,
                          endCenter: centre, endRadius: 165, options: [])

    // Arrow towards the Applications folder.
    rgb(255, 255, 255, 0.32).setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 258, y: fromTop(205)))
    shaft.line(to: NSPoint(x: 330, y: fromTop(205)))
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    shaft.stroke()

    rgb(255, 255, 255, 0.32).setFill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 326, y: fromTop(194)))
    head.line(to: NSPoint(x: 347, y: fromTop(205)))
    head.line(to: NSPoint(x: 326, y: fromTop(216)))
    head.close()
    head.fill()

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, topY: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributed = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
        let size = attributed.size()
        attributed.draw(in: NSRect(x: 0, y: fromTop(topY) - size.height / 2,
                                   width: width, height: size.height))
    }

    text("Warren", size: 30, weight: .semibold, color: rgb(255, 255, 255, 0.95), topY: 50)
    text("Drag Warren into your Applications folder", size: 13, weight: .regular,
         color: rgb(255, 255, 255, 0.55), topY: 84)
    text("Your tailnet, one click from the menu bar", size: 11, weight: .regular,
         color: rgb(255, 255, 255, 0.28), topY: 358)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
// One TIFF holding @1x and @2x, so the Finder picks the right one on Retina.
let image = NSImage(size: NSSize(width: width, height: height))
image.addRepresentation(draw(scale: 1))
image.addRepresentation(draw(scale: 2))
try! image.tiffRepresentation!.write(to: URL(fileURLWithPath: out))
try! draw(scale: 2).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".tiff", with: "-preview.png")))
