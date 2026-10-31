import SwiftUI
import AppKit

// A table with the Marg-style column controls, written for macOS 12+ (SwiftUI's own Table can only do this from macOS 14):
//   - drag the right edge of a heading to resize a column
//   - drag a heading sideways to move the column
//   - right-click a heading (or use the ⋯ button) to hide / show columns, or reset the layout
// The layout is remembered per table.

struct GridColumn<Row>: Identifiable {
    let id: String
    let title: String
    var min: CGFloat
    var ideal: CGFloat
    var align: Alignment
    var flex: Bool
    var hiddenByDefault: Bool
    var isIndex = false
    let cell: (Row) -> AnyView

    init<C: View>(_ title: String, id: String? = nil, min: CGFloat = 50, ideal: CGFloat = 100, align: Alignment = .leading,
                  flex: Bool = false, hidden: Bool = false, @ViewBuilder cell: @escaping (Row) -> C) {
        self.id = id ?? title
        self.title = title
        self.min = min
        self.ideal = ideal
        self.align = align
        self.flex = flex
        self.hiddenByDefault = hidden
        self.cell = { AnyView(cell($0)) }
    }
}

@resultBuilder
enum ColumnBuilder<Row> {
    static func buildExpression(_ c: GridColumn<Row>) -> [GridColumn<Row>] { [c] }
    static func buildExpression(_ c: [GridColumn<Row>]) -> [GridColumn<Row>] { c }
    static func buildBlock(_ parts: [GridColumn<Row>]...) -> [GridColumn<Row>] { parts.flatMap { $0 } }
    static func buildOptional(_ p: [GridColumn<Row>]?) -> [GridColumn<Row>] { p ?? [] }
    static func buildEither(first: [GridColumn<Row>]) -> [GridColumn<Row>] { first }
    static func buildEither(second: [GridColumn<Row>]) -> [GridColumn<Row>] { second }
}

/// What the user changed about one table: order, hidden columns and widths. Saved in UserDefaults.
final class GridLayout: ObservableObject {
    @Published var order: [String] = []
    @Published var hidden: Set<String> = []
    @Published var widths: [String: Double] = [:]
    @Published var touched = false
    private let key: String

    init(key: String) {
        self.key = "grid." + key
        if let d = UserDefaults.standard.data(forKey: self.key),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            order = (o["order"] as? [String]) ?? []
            hidden = Set((o["hidden"] as? [String]) ?? [])
            widths = ((o["widths"] as? [String: Double]) ?? [:])
            touched = true
        }
    }

    func save() {
        let o: [String: Any] = ["order": order, "hidden": Array(hidden), "widths": widths]
        if let d = try? JSONSerialization.data(withJSONObject: o) { UserDefaults.standard.set(d, forKey: key) }
    }

    func reset() {
        order = []; hidden = []; widths = [:]; touched = false
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct DataGrid<Row: Identifiable>: View where Row.ID: Hashable {
    let rows: [Row]
    let layoutKey: String
    var selection: Binding<Set<Row.ID>>?
    var rowHeight: CGFloat = 32
    var numbered = true
    var onOpen: ((Row) -> Void)?
    var menu: ((Row) -> AnyView)?
    let columns: [GridColumn<Row>]

    @StateObject private var layout: GridLayout
    @AppStorage("density") private var density = "regular"
    /// Row height after Settings › Appearance › Table rows.
    private var rh: CGFloat { rowHeight * Density.factor(density) }
    @State private var dragging: String?
    @State private var dragDX: CGFloat = 0
    @State private var resizing: (id: String, start: Double)?
    @State private var anchor: Int?   // row last clicked plain, for Shift-click range selection

    init(_ rows: [Row], layoutKey: String, selection: Binding<Set<Row.ID>>? = nil, rowHeight: CGFloat = 32,
         numbered: Bool = true, onOpen: ((Row) -> Void)? = nil, menu: ((Row) -> AnyView)? = nil,
         @ColumnBuilder<Row> columns: () -> [GridColumn<Row>]) {
        self.rows = rows
        self.layoutKey = layoutKey
        self.selection = selection
        self.rowHeight = rowHeight
        self.onOpen = onOpen
        self.menu = menu
        var cols = columns()
        // every table gets a serial number column first, unless the screen already has its own
        if numbered && !cols.contains(where: { $0.id == "sno" }) {
            var n = GridColumn<Row>("S.No", id: "sno", min: 44, ideal: 48, align: .trailing) { _ in EmptyView() }
            n.isIndex = true
            cols.insert(n, at: 0)
        }
        self.columns = cols
        _layout = StateObject(wrappedValue: GridLayout(key: layoutKey))
    }

    // MARK: layout maths

    private var orderedColumns: [GridColumn<Row>] {
        var byId: [String: GridColumn<Row>] = [:]
        for c in columns { byId[c.id] = c }
        var out: [GridColumn<Row>] = layout.order.compactMap { byId[$0] }
        if let n = columns.first(where: { $0.isIndex }), !layout.order.contains(n.id) { out.insert(n, at: 0) }   // saved layouts predate S.No
        let have = Set(out.map { $0.id })
        out += columns.filter { !have.contains($0.id) }
        return out
    }

    private func isHidden(_ c: GridColumn<Row>) -> Bool {
        layout.touched ? layout.hidden.contains(c.id) : c.hiddenByDefault
    }

    private var visible: [GridColumn<Row>] { orderedColumns.filter { !isHidden($0) } }

    private func baseWidth(_ c: GridColumn<Row>) -> CGFloat {
        let w = CGFloat(layout.widths[c.id] ?? Double(c.ideal))
        return Swift.max(c.min, w)
    }

    private func widths(_ cols: [GridColumn<Row>], avail: CGFloat) -> [CGFloat] {
        var w = cols.map(baseWidth)
        let total = w.reduce(0, +)
        if total < avail, !cols.isEmpty {
            let extra = avail - total
            let flexIdx = cols.indices.filter { cols[$0].flex }
            let targets = flexIdx.isEmpty ? [0] : flexIdx
            for i in targets { w[i] += extra / CGFloat(targets.count) }
        }
        return w
    }

    // MARK: edits

    private func commitOrder(_ cols: [GridColumn<Row>]) {
        layout.order = cols.map { $0.id }
        layout.touched = true
        layout.save()
    }

    private func materialise() {
        if !layout.touched {
            layout.hidden = Set(columns.filter { $0.hiddenByDefault }.map { $0.id })
            layout.order = columns.map { $0.id }
            layout.touched = true
        }
    }

    private func move(_ id: String, dx: CGFloat, cols: [GridColumn<Row>], widths w: [CGFloat]) {
        guard let from = cols.firstIndex(where: { $0.id == id }) else { return }
        let startX = w[0..<from].reduce(0, +)
        let centre = startX + w[from] / 2 + dx
        var acc: CGFloat = 0
        var to = cols.count - 1
        for (i, x) in w.enumerated() {
            if centre < acc + x { to = i; break }
            acc += x
        }
        guard to != from else { return }
        materialise()
        var all = orderedColumns
        let vis = cols
        // move within the full ordered list so hidden columns keep their place
        guard let fi = all.firstIndex(where: { $0.id == vis[from].id }), let ti = all.firstIndex(where: { $0.id == vis[to].id }) else { return }
        let c = all.remove(at: fi)
        all.insert(c, at: ti)
        commitOrder(all)
    }

    private func toggle(_ c: GridColumn<Row>) {
        materialise()
        if layout.hidden.contains(c.id) { layout.hidden.remove(c.id) } else if visible.count > 1 { layout.hidden.insert(c.id) }
        layout.save()
    }

    /// Plain click: select only this row (and remember it as the anchor for a later Shift-click).
    /// ⌘-click: add/remove just this row. ⇧-click: select every row between the anchor and here.
    private func click(_ row: Row, _ idx: Int) {
        guard let selection else { return }
        let mods = NSEvent.modifierFlags
        if mods.contains(.shift), let a = anchor {
            let lo = Swift.min(a, idx), hi = Swift.max(a, idx)
            guard lo >= 0, hi < rows.count else { selection.wrappedValue = [row.id]; anchor = idx; return }
            selection.wrappedValue.formUnion(rows[lo...hi].map { $0.id })
        } else if mods.contains(.command) {
            if selection.wrappedValue.contains(row.id) { selection.wrappedValue.remove(row.id) } else { selection.wrappedValue.insert(row.id) }
            anchor = idx
        } else {
            selection.wrappedValue = [row.id]
            anchor = idx
        }
    }

    // MARK: views

    var body: some View {
        GeometryReader { geo in
            let cols = visible
            let w = widths(cols, avail: geo.size.width - 28)
            let total = w.reduce(0, +) + 28
            let full = Swift.max(total, geo.size.width)
            ScrollView(.horizontal, showsIndicators: total > geo.size.width) {
                // heading and rows live in the SAME vertical scroll view (the heading is pinned), so they always share one width:
                // a scroll bar can never push the rows out of line with the heading
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section(header:
                            VStack(spacing: 0) {
                                header(cols, w)
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }
                            .background(Theme.page)
                        ) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                                rowView(row, idx, cols, w)
                            }
                        }
                    }
                    .frame(width: full)
                }
                .frame(width: full, height: geo.size.height)
            }
        }
        .background(Theme.page)
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 0.5))
    }

    private func header(_ cols: [GridColumn<Row>], _ w: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cols.enumerated()), id: \.element.id) { i, c in
                headerCell(c, width: w[i], cols: cols, widths: w)
            }
            Menu {
                columnMenu
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 28, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .help("Show or hide columns")
        }
        .background(Theme.card)
        .contextMenu { columnMenu }
    }

    // one column heading: title (drag to move) and the resize handle on its right edge
    private func headerCell(_ c: GridColumn<Row>, width: CGFloat, cols: [GridColumn<Row>], widths w: [CGFloat]) -> some View {
        ZStack(alignment: .trailing) {
            headerTitle(c, width: width, cols: cols, widths: w)
            Rectangle().fill(Theme.line).frame(width: 1, height: 26)
            resizeHandle(c, width: width)
        }
        .frame(width: width)
    }

    private func headerTitle(_ c: GridColumn<Row>, width: CGFloat, cols: [GridColumn<Row>], widths w: [CGFloat]) -> some View {
        let moving = dragging == c.id
        let drag = DragGesture(minimumDistance: 10)
            .onChanged { v in dragging = c.id; dragDX = v.translation.width }
            .onEnded { v in
                move(c.id, dx: v.translation.width, cols: cols, widths: w)
                dragging = nil; dragDX = 0
            }
        return Text(c.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: 28, alignment: c.align)
            .contentShape(Rectangle())
            .offset(x: moving ? dragDX : 0)
            .zIndex(moving ? 1 : 0)
            .opacity(moving ? 0.7 : 1)
            .gesture(drag)
    }

    private func resizeHandle(_ c: GridColumn<Row>, width: CGFloat) -> some View {
        let drag = DragGesture(minimumDistance: 1)
            .onChanged { v in
                if resizing?.id != c.id { resizing = (c.id, Double(width)) }
                materialise()
                layout.widths[c.id] = Swift.max(Double(c.min), (resizing?.start ?? Double(width)) + Double(v.translation.width))
            }
            .onEnded { _ in resizing = nil; layout.save() }
        return Color.clear.frame(width: 8, height: 26).contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(drag)
    }

    @ViewBuilder private var columnMenu: some View {
        ForEach(orderedColumns) { c in
            Button {
                toggle(c)
            } label: {
                if isHidden(c) { Text(c.title) } else { Label(c.title, systemImage: "checkmark") }
            }
        }
        Divider()
        Button("Reset columns") { layout.reset() }
    }

    private func rowView(_ row: Row, _ idx: Int, _ cols: [GridColumn<Row>], _ w: [CGFloat]) -> some View {
        let selected = selection?.wrappedValue.contains(row.id) ?? false
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(cols.enumerated()), id: \.element.id) { i, c in
                    Group {
                        if c.isIndex {
                            HStack(spacing: 6) {
                                // a tick box per row: tick several rows, then act on them (print, delete…)
                                if let selection {
                                    Button { if selected { selection.wrappedValue.remove(row.id) } else { selection.wrappedValue.insert(row.id) } } label: {
                                        Image(systemName: selected ? "checkmark.square.fill" : "square").foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(selected ? "Untick" : "Tick this row")
                                }
                                Text("\(idx + 1)").mono().foregroundStyle(.secondary)
                            }
                        } else { c.cell(row) }
                    }
                        .padding(.horizontal, 10)
                        .frame(width: w[i], height: rh, alignment: c.align)
                        .clipped()
                        
                }
                Color.clear.frame(width: 28, height: rh)   // same width as the heading's column-menu button
            }
            Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 0.5)
        }
        .background(selected ? Color.accentColor.opacity(0.14) : Theme.card)
        .contentShape(Rectangle())
        .modifier(RowTaps(enabled: selection != nil, single: { click(row, idx) }, double: { onOpen?(row) }))
        .contextMenu { if let menu { menu(row) } }
    }
}

private struct RowTaps: ViewModifier {
    let enabled: Bool
    let single: () -> Void
    let double: () -> Void
    func body(content: Content) -> some View {
        if enabled {
            content
                .onTapGesture(count: 2) { single(); double() }
                .onTapGesture { single() }
        } else {
            content
        }
    }
}
