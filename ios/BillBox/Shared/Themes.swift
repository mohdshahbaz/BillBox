import SwiftUI
import UIKit

/// Colour themes (the same on the Mac). Each has an accent colour plus page and card backgrounds for light and dark mode.
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
        // calm greys, white panels, one indigo accent (the default)
        AppTheme(id: "clean", name: "Clean", accent: dyn(0x4F46E5, 0x8B8CF8), card: dyn(0xFFFFFF, 0x17171A), page: dyn(0xF6F6F7, 0x0C0C0E), swatch: [hex(0x4F46E5), hex(0xF6F6F7)]),
        AppTheme(id: "classic", name: "Classic", accent: Color(UIColor.systemBlue), card: Color(UIColor.secondarySystemGroupedBackground), page: Color(UIColor.systemGroupedBackground), swatch: [hex(0x0A84FF), hex(0xE8E8ED)]),
        AppTheme(id: "ocean", name: "Ocean", accent: dyn(0x0E7C9B, 0x35B6D6), card: dyn(0xFFFFFF, 0x17272F), page: dyn(0xEAF4F8, 0x0F1C22), swatch: [hex(0x0E7C9B), hex(0xBFE3EE)]),
        AppTheme(id: "forest", name: "Forest", accent: dyn(0x2E7D52, 0x4FBF82), card: dyn(0xFFFFFF, 0x18261D), page: dyn(0xEBF4EE, 0x101A14), swatch: [hex(0x2E7D52), hex(0xC4E4D0)]),
        AppTheme(id: "sunset", name: "Sunset", accent: dyn(0xD9552B, 0xFF7F50), card: dyn(0xFFFFFF, 0x2E1D14), page: dyn(0xFCF0E8, 0x21150F), swatch: [hex(0xD9552B), hex(0xFAD3BE)]),
        AppTheme(id: "royal", name: "Royal", accent: dyn(0x6D3FD0, 0x9B7BF0), card: dyn(0xFFFFFF, 0x241C38), page: dyn(0xF2EEFA, 0x181325), swatch: [hex(0x6D3FD0), hex(0xD9CCF5)]),
        AppTheme(id: "rose", name: "Rose", accent: dyn(0xC9285F, 0xF0608F), card: dyn(0xFFFFFF, 0x2B1821), page: dyn(0xFBEEF3, 0x22141A), swatch: [hex(0xC9285F), hex(0xF6C9D8)]),
        AppTheme(id: "gold", name: "Marigold", accent: dyn(0xB7791F, 0xF2B544), card: dyn(0xFFFFFF, 0x2A2316), page: dyn(0xFBF5E6, 0x1E190F), swatch: [hex(0xB7791F), hex(0xF5E2B4)]),
        AppTheme(id: "slate", name: "Slate", accent: dyn(0x4A5C70, 0x93A8BD), card: dyn(0xFFFFFF, 0x25282C), page: dyn(0xEEF0F3, 0x1B1D20), swatch: [hex(0x4A5C70), hex(0xCDD5DE)]),
        AppTheme(id: "midnight", name: "Midnight", accent: dyn(0x2563EB, 0x60A5FA), card: dyn(0xFFFFFF, 0x111827), page: dyn(0xEEF2F7, 0x0B1220), swatch: [hex(0x2563EB), hex(0x1E293B)]),
        AppTheme(id: "mint", name: "Mint", accent: dyn(0x0F9D7A, 0x34D3A6), card: dyn(0xFFFFFF, 0x16241F), page: dyn(0xEAF7F2, 0x0F1A16), swatch: [hex(0x0F9D7A), hex(0xC6F0E2)]),
        AppTheme(id: "lavender", name: "Lavender", accent: dyn(0x7C5CC4, 0xB49CFF), card: dyn(0xFFFFFF, 0x221D2E), page: dyn(0xF4F0FB, 0x17131F), swatch: [hex(0x7C5CC4), hex(0xE4DBF7)]),
        AppTheme(id: "saffron", name: "Saffron", accent: dyn(0xE07000, 0xFFA733), card: dyn(0xFFFFFF, 0x2B2112), page: dyn(0xFFF5E6, 0x1F170C), swatch: [hex(0xE07000), hex(0xFFE2B8)]),
        AppTheme(id: "crimson", name: "Crimson", accent: dyn(0xB91C1C, 0xF87171), card: dyn(0xFFFFFF, 0x2A1616), page: dyn(0xFBEFEF, 0x1E1010), swatch: [hex(0xB91C1C), hex(0xF5CFCF)]),
        AppTheme(id: "coffee", name: "Coffee", accent: dyn(0x7A4E2D, 0xC9925E), card: dyn(0xFFFFFF, 0x2A211B), page: dyn(0xF6EFE8, 0x1C1612), swatch: [hex(0x7A4E2D), hex(0xE9D8C6)]),
        AppTheme(id: "graphite", name: "Graphite", accent: dyn(0x1F2937, 0xE5E7EB), card: dyn(0xFFFFFF, 0x1C1C1E), page: dyn(0xF2F2F3, 0x000000), swatch: [hex(0x1F2937), hex(0xD1D5DB)]),
    ]

    static func named(_ id: String) -> AppTheme { all.first { $0.id == id } ?? all[0] }
    /// The chosen theme. Asked for by every table row and panel, so it is looked up once per theme change, not each time.
    private static var cached: (id: String, theme: AppTheme)?
    static var current: AppTheme {
        let id = UserDefaults.standard.string(forKey: "theme") ?? "clean"
        if let c = cached, c.id == id { return c.theme }
        let t = named(id)
        cached = (id, t)
        return t
    }
}

/// Settings > Appearance: pick a colour theme and light / dark / automatic.
@MainActor struct AppearanceSettings: View {
    @AppStorage("theme") private var themeId = "clean"
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("cardStyle") private var cardStyle = "soft"
    @AppStorage("corners") private var corners = "normal"
    @AppStorage("density") private var density = "regular"
    @AppStorage("textSize") private var textSize = "default"
    @AppStorage("fontStyle") private var fontStyle = "system"
    @AppStorage("fontWeight") private var fontWeight = "regular"

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
                    Text("Letters").font(.headline)
                    Picker("Typeface", selection: $fontStyle) {
                        ForEach(FontChoice.families, id: \.id) { f in Text(f.name).font(FontChoice.sample(f.id)).tag(f.id) }
                    }
                    .pickerStyle(.menu)
                    Picker("Weight", selection: $fontWeight) {
                        Text("Light").tag("light"); Text("Regular").tag("regular"); Text("Medium").tag("medium"); Text("Bold").tag("bold")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text("Letters change at once in the whole app. System, Rounded, Serif (New York), Mono, Condensed, Expanded and Compressed change every word; the named typefaces (Avenir Next, Georgia …) change the text of lists, fields and buttons, with headings in the matching system style.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

/// Settings › Appearance › Letters: the app's typeface (San Francisco, its rounded form, New York serif or monospaced) and weight.
struct FontChoice: ViewModifier {
    @AppStorage("fontStyle") private var style = "system"
    @AppStorage("fontWeight") private var weight = "regular"

    struct Family { let id: String; let name: String; let custom: String?; let design: String }
    /// The choices. System styles change every word; a named typeface (built into iPhone, iPad and Mac) becomes the
    /// text of the app, and headings take the system style closest to it.
    static let families: [Family] = [
        Family(id: "system", name: "System (San Francisco)", custom: nil, design: "default"),
        Family(id: "rounded", name: "Rounded", custom: nil, design: "rounded"),
        Family(id: "serif", name: "Serif (New York)", custom: nil, design: "serif"),
        Family(id: "mono", name: "Mono", custom: nil, design: "mono"),
        Family(id: "condensed", name: "Condensed", custom: nil, design: "condensed"),
        Family(id: "expanded", name: "Expanded", custom: nil, design: "expanded"),
        Family(id: "compressed", name: "Compressed", custom: nil, design: "compressed"),
        Family(id: "avenir", name: "Avenir Next", custom: "AvenirNext-Regular", design: "default"),
        Family(id: "helvetica", name: "Helvetica Neue", custom: "HelveticaNeue", design: "default"),
        Family(id: "futura", name: "Futura", custom: "Futura-Medium", design: "default"),
        Family(id: "gillsans", name: "Gill Sans", custom: "GillSans", design: "default"),
        Family(id: "optima", name: "Optima", custom: "Optima-Regular", design: "default"),
        Family(id: "georgia", name: "Georgia", custom: "Georgia", design: "serif"),
        Family(id: "palatino", name: "Palatino", custom: "Palatino-Roman", design: "serif"),
        Family(id: "baskerville", name: "Baskerville", custom: "Baskerville", design: "serif"),
        Family(id: "typewriter", name: "American Typewriter", custom: "AmericanTypewriter", design: "serif"),
        Family(id: "menlo", name: "Menlo", custom: "Menlo-Regular", design: "mono"),
    ]
    static func family(_ id: String) -> Family { families.first { $0.id == id } ?? families[0] }

    /// The name in the menu, written in its own letters.
    static func sample(_ id: String) -> Font {
        let f = family(id)
        if let c = f.custom { return .custom(c, size: 15) }
        switch f.design {
        case "rounded": return .system(size: 15, design: .rounded)
        case "serif": return .system(size: 15, design: .serif)
        case "mono": return .system(size: 15, design: .monospaced)
        default: return .system(size: 15)
        }
    }

    @ViewBuilder func body(content: Content) -> some View {
        let f = Self.family(style)
        let w: Font.Weight? = weight == "light" ? .light : weight == "medium" ? .medium : weight == "bold" ? .semibold : nil
        let base = f.custom.map { Font.custom($0, size: 17, relativeTo: .body) }
        if #available(iOS 16.4, *) {
            content
                .fontDesign(f.design == "rounded" ? .rounded : f.design == "serif" ? .serif : f.design == "mono" ? .monospaced : .default)
                .fontWidth(f.design == "condensed" ? .condensed : f.design == "expanded" ? .expanded : f.design == "compressed" ? .compressed : nil)
                .fontWeight(w)
                .optionalFont(base)
        } else if #available(iOS 16.1, *) {
            content
                .fontDesign(f.design == "rounded" ? .rounded : f.design == "serif" ? .serif : f.design == "mono" ? .monospaced : .default)
                .fontWeight(w)
                .optionalFont(base)
        } else {
            content.optionalFont(base)
        }
    }
}

extension View {
    /// `.font(f)` only when there is one (a nil font would undo the text size chosen around it).
    @ViewBuilder func optionalFont(_ f: Font?) -> some View {
        if let f { self.font(f) } else { self }
    }
}
