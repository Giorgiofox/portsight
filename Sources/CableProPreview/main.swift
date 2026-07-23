import SwiftUI
import AppKit
import CableProUI

// Offscreen renderer for design review + icon generation.
//   swift run CableProPreview [output.png]        → popover mockup
//   swift run CableProPreview --icon [out.png]    → 1024px app icon

@MainActor
func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)  (\(Int(image.size.width))×\(Int(image.size.height)))")
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1)
    }
}

@MainActor
func renderIcon() {
    let args = CommandLine.arguments
    let out = args.count > 2 ? args[2] : "/tmp/portsight-icon.png"
    let renderer = ImageRenderer(content: AppIconView().frame(width: 1024, height: 1024))
    renderer.scale = 1
    guard let image = renderer.nsImage else {
        FileHandle.standardError.write(Data("icon render failed\n".utf8)); exit(1)
    }
    writePNG(image, to: out)
}

@MainActor
func renderPreview() {
    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/portsight-preview.png"
    // ImageRenderer can't draw Materials and ignores scene color-scheme, so
    // render in flat mode with an explicit dark environment.
    Theme.flat = true
    let view = ContentView(model: .preview(), live: false, scroll: false)
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    writePNG(image, to: out)
}

@MainActor
func renderDashboard() {
    let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/portsight-dashboard.png"
    Theme.flat = true
    let view = DashboardView(model: .preview(), live: false, scroll: false)
        .frame(width: 900)
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    writePNG(image, to: out)
}

MainActor.assumeIsolated {
    switch CommandLine.arguments.dropFirst().first {
    case "--icon": renderIcon()
    case "--dashboard": renderDashboard()
    default: renderPreview()
    }
}
