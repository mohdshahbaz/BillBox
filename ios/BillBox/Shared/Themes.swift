import SwiftUI
import UIKit

/// Colour themes (same eight as the Mac). Each has an accent colour plus page and card backgrounds for light and dark mode.
struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let accent: Color
    let card: Color
    let page: Color
    let swatch: [Color]

    private static func ui(_ h: UInt32) -> UIColor {
        UIColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
    }
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        let l = ui(light), d = ui(dark)
        return Color(UIColor { tc in tc.userInterfaceStyle == .dark ? d : l })
    }
    private static func hex(_ h: UInt32) -> Color { Color(ui(h)) }

    static let all: [AppTheme] = [
        AppTheme(id: "classic", name: "Classic", accent: Color(UIColor.systemBlue), card: Color(UIColor.secondarySystemGroupedBackground), page: Color(UIColor.systemGroupedBackground), swatch: [hex(0x0A84FF), hex(0xE8E8ED)]),
        AppTheme(id: "ocean", name: "Ocean", accent: dyn(0x0E7C9B, 0x35B6D6), card: dyn(0xFFFFFF, 0x17272F), page: dyn(0xEAF4F8, 0x0F1C22), swatch: [hex(0x0E7C9B), hex(0xBFE3EE)]),
        AppTheme(id: "forest", name: "Forest", accent: dyn(0x2E7D52, 0x4FBF82), card: dyn(0xFFFFFF, 0x18261D), page: dyn(0xEBF4EE, 0x101A14), swatch: [hex(0x2E7D52), hex(0xC4E4D0)]),
        AppTheme(id: "sunset", name: "Sunset", accent: dyn(0xD9552B, 0xFF7F50), card: dyn(0xFFFFFF, 0x2E1D14), page: dyn(0xFCF0E8, 0x21150F), swatch: [hex(0xD9552B), hex(0xFAD3BE)]),
        AppTheme(id: "royal", name: "Royal", accent: dyn(0x6D3FD0, 0x9B7BF0), card: dyn(0xFFFFFF, 0x241C38), page: dyn(0xF2EEFA, 0x181325), swatch: [hex(0x6D3FD0), hex(0xD9CCF5)]),
        AppTheme(id: "rose", name: "Rose", accent: dyn(0xC9285F, 0xF0608F), card: dyn(0xFFFFFF, 0x2B1821), page: dyn(0xFBEEF3, 0x22141A), swatch: [hex(0xC9285F), hex(0xF6C9D8)]),
        AppTheme(id: "gold", name: "Marigold", accent: dyn(0xB7791F, 0xF2B544), card: dyn(0xFFFFFF, 0x2A2316), page: dyn(0xFBF5E6, 0x1E190F), swatch: [hex(0xB7791F), hex(0xF5E2B4)]),
        AppTheme(id: "slate", name: "Slate", accent: dyn(0x4A5C70, 0x93A8BD), card: dyn(0xFFFFFF, 0x25282C), page: dyn(0xEEF0F3, 0x1B1D20), swatch: [hex(0x4A5C70), hex(0xCDD5DE)]),
    ]

    static func named(_ id: String) -> AppTheme { all.first { $0.id == id } ?? all[0] }
    static var current: AppTheme { named(UserDefaults.standard.string(forKey: "theme") ?? "classic") }
}

/// Settings > Appearance: pick a colour theme and light / dark / automatic.
@MainActor struct AppearanceSettings: View {
    @AppStorage("theme") private var themeId = "classic"
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("cardStyle") private var cardStyle = "soft"
    @AppStorage("corners") private var corners = "normal"
    @AppStorage("density") private var density = "regular"
    @AppStorage("textSize") private var textSize = "default"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Theme").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                    ForEach(AppTheme.all) { t in
                        Button { themeId = t.id } label: {
                            VStack(spacing: 8) {
                                HStack(spacing: 0) {
                                    Rectangle().fill(t.swatch[0])
                                    Rectangle().fill(t.swatch[1])
                                }
                                .frame(height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                HStack {
                                    Text(t.name).font(.callout.weight(.medium)).foregroundColor(.primary)
                                    Spacer()
                                    if themeId == t.id { Image(systemName: "checkmark.circle.fill").foregroundColor(t.swatch[0]) }
                                }
                            }
                            .padding(10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeId == t.id ? t.swatch[0] : Color.gray.opacity(0.25), lineWidth: themeId == t.id ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(t.name) theme" + (themeId == t.id ? ", selected" : ""))
                    }
                }
                Text("Mode").font(.headline)
                Picker("Mode", selection: $appearance) {
                    Text("Automatic").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented).labelsHidden()
                Group {
                    Text("Panels").font(.headline)
                    Picker("Panels", selection: $cardStyle) {
                        Text("Soft shadow").tag("soft"); Text("Outlined").tag("outline"); Text("Flat").tag("flat")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Picker("Corners", selection: $corners) {
                        Text("Square").tag("square"); Text("Rounded").tag("normal"); Text("Round").tag("round")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text("Table rows").font(.headline)
                    Picker("Rows", selection: $density) {
                        Text("Compact").tag("compact"); Text("Regular").tag("regular"); Text("Roomy").tag("roomy")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text("Text size").font(.headline)
                    Picker("Size", selection: $textSize) {
                        Text("Smaller").tag("small"); Text("System").tag("default"); Text("Larger").tag("large"); Text("Largest").tag("xlarge")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text("Panels, corners, row height and text size apply at once on this iPhone and are remembered.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("The theme changes the accent colour and the page and panel backgrounds. It applies at once and is remembered.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.page)
        .navigationTitle("Appearance")
    }
}
