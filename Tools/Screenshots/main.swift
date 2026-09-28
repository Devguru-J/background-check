import BackgroundCheckCore
import AppKit
import SwiftUI

let outDir = CommandLine.arguments[1]

func session(_ pid: Int32, _ name: String, _ tool: String, _ ports: [Int], _ uptime: TimeInterval, cmd: String) -> DevSession {
    DevSession(rootPID: pid, memberPIDs: [pid, pid + 1, pid + 2], command: cmd, ignoreKey: cmd, toolName: tool,
               projectName: name, projectPath: NSHomeDirectory() + "/Devguru/\(name)", ports: ports, uptime: uptime,
               isStale: uptime >= 6 * 3600)
}

let samples = [
    session(4101, "portfolio", "astro dev", [4321], 3 * 86400 + 2 * 3600,
            cmd: "npm run dev"),
    session(5230, "shop-api", "nodemon", [3000], 7 * 3600 + 12 * 60,
            cmd: "node ./node_modules/.bin/nodemon src/index.ts"),
    session(6112, "docs", "vite", [5173], 18 * 60,
            cmd: "node ./node_modules/.bin/vite"),
    session(7004, "ml-playground", "uvicorn", [8000], 4 * 60,
            cmd: "python -m uvicorn app.main:app --reload"),
]

@MainActor
func write<V: View>(_ view: V, _ name: String) {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
    let size = host.fittingSize
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("no rep \(name)"); return }
    host.cacheDisplay(in: host.bounds, to: rep)
    window.orderOut(nil)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    print("wrote \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.28), Color(red: 0.33, green: 0.16, blue: 0.42),
                                    Color(red: 0.85, green: 0.42, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(0.18), .clear], center: .init(x: 0.75, y: 0.1),
                           startRadius: 10, endRadius: 420)
        }
    }
}

struct MenuBarStrip<Trailing: View>: View {
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.bold)
            Text("파일"); Text("편집"); Text("보기")
            Spacer()
            trailing
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("9월 28일 (일) 오후 2:14")
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(Color.black.opacity(0.25))
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
    }
}

struct Hero: View {
    let model: AppModel
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Wallpaper()
            VStack(spacing: 0) {
                MenuBarStrip {
                    MenuBarLabel(count: model.sessions.count, hasStale: model.staleCount > 0)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
                HStack {
                    Spacer()
                    Panel { MenuPanelView(model: model) }
                        .padding(.trailing, 200)
                        .padding(.top, 6)
                }
                Spacer()
            }
        }
        .frame(width: 960, height: 520)
    }
}

struct RowDetail: View {
    var body: some View {
        ZStack {
            Wallpaper()
            Panel {
                VStack(spacing: 1) {
                    SessionRowView(session: samples[0], isExpanded: true, isTerminating: false, error: nil,
                                   onToggle: {}, onTerminate: {}, onIgnore: {})
                    SessionRowView(session: samples[1], isExpanded: false, isTerminating: true, error: nil,
                                   onToggle: {}, onTerminate: {}, onIgnore: {})
                }
                .padding(5)
                .frame(width: 320)
                .background(MenuMaterialBackground())
            }
        }
        .frame(width: 520, height: 300)
    }
}

struct SettingsShot: View {
    let model: AppModel
    var body: some View {
        ZStack {
            Wallpaper()
            Panel {
                VStack(spacing: 0) {
                    ZStack {
                        HStack(spacing: 8) {
                            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                            Spacer()
                        }
                        .frame(height: 12)
                        Text("Background Check 설정").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    SettingsView(model: model)
                }
                .background(Color(red: 0.12, green: 0.12, blue: 0.13))
            }
            .padding(40)
        }
    }
}

struct EmptyHero: View {
    var body: some View {
        ZStack {
            Wallpaper()
            Panel { MenuPanelView(model: AppModel(sessions: [], settings: .defaults(home: "/Users/you"))) }
        }
        .frame(width: 520, height: 300)
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let home = NSHomeDirectory()
    let settings = ScanSettings(projectRoots: [home + "/Devguru", home + "/Documents"], staleHours: 6,
                                ignorePatterns: ["bot/daemon.js", "storybook dev -p 6006"])
    let model = AppModel(sessions: samples, settings: settings)
    write(Hero(model: model), "panel.png")
    write(RowDetail(), "row-detail.png")
    write(EmptyHero(), "empty.png")
    write(SettingsShot(model: model), "settings.png")
}
