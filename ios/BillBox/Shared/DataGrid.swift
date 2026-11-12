import SwiftUI

// The Mac's adjustable table, for iPhone and iPad:
//   - every column is kept; the table scrolls sideways with the heading pinned on top
//   - drag the grip at the right edge of a heading to resize a column
//   - "⋯" (or a long press on the heading) opens Columns: show / hide, move up / down, reset
//   - long press a row for its menu; in Select mode a tap selects
// The layout is remembered per table in the same format as on the Mac ("grid.<key>": order, hidden, widths).

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
    var selecting: Binding<Bool>?
    var rowHeight: CGFloat = 36
    /// false for short, editable tables (the bill): every row is kept, so editing never loses the keyboard
    var lazy = true
    var onOpen: ((Row) -> Void)?
    var menu: ((Row) -> AnyView)?
    let columns: [GridColumn<Row>]

    @StateObject private var layout: GridLayout
    @AppStorage("density") private var density = "regular"
    @AppStorage("stripes") private var stripes = false
    /// Row height after Settings › Appearance › Table rows.
    private var rh: CGFloat { rowHeight * Density.factor(density) }
    @State private var resizing: (id: String, start: Double)?
    @State private var showColumns = false
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(_ rows: [Row], layoutKey: String, selection: Binding<Set<Row.ID>>? = nil, selecting: Binding<Bool>? = nil, rowHeight: CGFloat = 36,
         lazy: Bool = true, numbered: Bool = true, onOpen: ((Row) -> Void)? = nil, menu: ((Row) -> AnyView)? = nil,
         @ColumnBuilder<Row> columns: () -> [GridColumn<Row>]) {
        self.rows = rows
        self.layoutKey = layoutKey
        self.selection = selection
        self.selecting = selecting
        self.rowHeight = rowHeight
        self.lazy = lazy
        self.onOpen = onOpen
        self.menu = menu
        var cols = columns()
        // every table gets a serial number column first, unless the screen already has its own
        if numbered && !cols.contains(where: { $0.id == "sno" }) {
            var n = GridColumn<Row>("S.No", id: "sno", min: selection != nil ? 60 : 44, ideal: selection != nil ? 64 : 48, align: .trailing) { _ in EmptyView() }
            n.isIndex = true
            cols.insert(n, at: 0)
        }
        self.columns = cols
        _layout = StateObject(wrappedValue: GridLayout(key: layoutKey))
    }

    // MARK: layout maths

    var orderedColumns: [GridColumn<Row>] { layout.ordered(columns) }
    func isHidden(_ c: GridColumn<Row>) -> Bool { layout.isHidden(c) }
    private var visible: [GridColumn<Row>] { orderedColumns.filter { !isHidden($0) } }

    private func baseWidth(_ c: GridColumn<Row>) -> CGFloat {
        let w = layout.widths[c.id].map { CGFloat($0) } ?? c.ideal * max(1, min(scale, 1.6))
        return Swift.max(c.min, w)
    }

    private func widths(_ cols: [GridColumn<Row>], avail: CGFloat) -> [CGFloat] {
        var w = cols.map(baseWidth)
        let total = w.reduce(0, +)
        if total < avail, !cols.isEmpty {
            let extra = avail - total
            let flexIdx = cols.indices.filter { cols[$0].flex }
            let targets = flexIdx.isEmpty ? [cols.count - 1] : flexIdx
            for i in targets { w[i] += extra / CGFloat(targets.count) }
        }
        return w
    }

    func materialise() { layout.materialise(columns) }
    func toggle(_ c: GridColumn<Row>) { layout.toggle(c, columns) }

    private var isSelecting: Bool { selecting?.wrappedValue ?? false }

    private func tap(_ row: Row) {
        if let selection, isSelecting || onOpen == nil {
            if selection.wrappedValue.contains(row.id) { selection.wrappedValue.remove(row.id) } else { selection.wrappedValue.insert(row.id) }
        } else {
            onOpen?(row)
        }
    }

    // MARK: views

    var body: some View {
        GeometryReader { geo in
            let cols = visible
            let w = widths(cols, avail: Swift.max(0, geo.size.width - 36))
            let total = w.reduce(0, +) + 36
            let full = Swift.max(total, geo.size.width)
            ScrollView(.horizontal, showsIndicators: total > geo.size.width) {
                ScrollView(.vertical) {
                    if lazy {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section(header: headerBlock(cols, w)) {
                                // by position: a lazy stack crashes when two rows report the same id, and report rows may lack one
                                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                    rowView(row, idx, cols, w)
                                }
                            }
                        }
                        .frame(width: full)
                    } else {
                        // every row stays alive (the bill being typed): a text field being edited is never thrown away when the
                        // keyboard makes the table shorter, so the number pad does not close in the middle of typing
                        VStack(spacing: 0) {
                            headerBlock(cols, w)
                            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                rowView(row, idx, cols, w)
                            }
                        }
                        .frame(width: full)
                    }
                }
                .scrollDismissesKeyboard(.never)
                .frame(width: full, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        // A scroll view that touches the bottom edge stretches under the tab bar / bottom toolbar, and when it sits inside the
        // sideways scroller it gets no inset for them, so the last rows hid behind the buttons. One point of padding keeps the
        // grid inside the visible area; the clip keeps rows from being drawn under the bars.
        .padding(.bottom, 1)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
        .padding(.horizontal, 10).padding(.bottom, 6)
        .sheet(isPresented: $showColumns) { ColumnSheet(layout: layout, columns: columns) }
    }

    private func headerBlock(_ cols: [GridColumn<Row>], _ w: [CGFloat]) -> some View {
        VStack(spacing: 0) {
            header(cols, w)
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
        .background(Theme.card)
    }

    private func header(_ cols: [GridColumn<Row>], _ w: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cols.enumerated()), id: \.element.id) { i, c in
                ZStack(alignment: .trailing) {
                    Text(c.title).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                        .frame(width: w[i], alignment: c.align)
                        .frame(minHeight: 34)
                        .accessibilityAddTraits(.isHeader)
                    // resize grip on the right edge
                    Rectangle().fill(Theme.line.opacity(0.6)).frame(width: 1, height: 16)
                    Color.clear.frame(width: 14).contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .global)   // the handle moves with the edge: local space fed back into itself
                                .onChanged { v in
                                    if resizing?.id != c.id { resizing = (c.id, Double(w[i])) }
                                    materialise()
                                    layout.widths[c.id] = Swift.max(Double(c.min), (resizing?.start ?? Double(w[i])) + Double(v.translation.width))
                                }
                                .onEnded { _ in resizing = nil; layout.save() }
                        )
                        .accessibilityHidden(true)
                }
                .frame(width: w[i])
            }
            Button { showColumns = true } label: {
                Image(systemName: "ellipsis.circle").frame(width: 36, height: 32)
            }
            .accessibilityLabel("Columns")
        }
        .background(Theme.accent.opacity(0.06))
        .contextMenu {
            ForEach(orderedColumns) { c in
                Button { toggle(c) } label: {
                    if isHidden(c) { Text(c.title) } else { Label(c.title, systemImage: "checkmark") }
                }
            }
            Divider()
            Button("Columns…") { showColumns = true }
            Button("Reset columns") { layout.reset() }
        }
    }

    private func rowView(_ row: Row, _ idx: Int, _ cols: [GridColumn<Row>], _ w: [CGFloat]) -> some View {
        let selected = selection?.wrappedValue.contains(row.id) ?? false
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(cols.enumerated()), id: \.element.id) { i, c in
                    Group {
                        if c.isIndex {
                            HStack(spacing: 4) {
                                // the tick circle always in the same place, the number on the right
                                if isSelecting { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.accent : Color.secondary) }
                                Spacer(minLength: 0)
                                Text("\(idx + 1)").monospacedDigit().foregroundStyle(.secondary).lineLimit(1).fixedSize()
                            }
                        } else { c.cell(row) }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: w[i], alignment: c.align)
                    .frame(minHeight: rh)
                    .clipped()
                    
                }
                Color.clear.frame(width: 36, height: 1)
            }
            Rectangle().fill(Theme.line.opacity(0.45)).frame(height: 0.5).padding(.leading, 12)
        }
        .background(selected ? Theme.accent.opacity(0.14) : (stripes && idx % 2 == 1 ? Theme.accent.opacity(0.05) : Color.clear))
        .background(Theme.card)
        .contentShape(Rectangle())
        .onTapGesture { tap(row) }
        .contextMenu { if let menu { menu(row) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Columns: show / hide, reorder, reset.
private struct ColumnSheet<Row>: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var layout: GridLayout
    let columns: [GridColumn<Row>]

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("Drag the handles to change the order. Drag the right edge of a heading in the table to change a column's width.")) {
                    ForEach(layout.ordered(columns)) { c in
                        Button { layout.toggle(c, columns) } label: {
                            HStack {
                                Image(systemName: layout.isHidden(c) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(layout.isHidden(c) ? Color.secondary : Theme.accent)
                                Text(c.title).foregroundColor(.primary)
                            }
                        }
                        .accessibilityLabel(c.title + (layout.isHidden(c) ? ", hidden" : ", shown"))
                    }
                    .onMove { from, to in layout.move(from, to, columns) }
                }
                Section {
                    Button("Reset columns", role: .destructive) { layout.reset() }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

extension GridLayout {
    func ordered<R>(_ columns: [GridColumn<R>]) -> [GridColumn<R>] {
        var byId: [String: GridColumn<R>] = [:]
        for c in columns { byId[c.id] = c }
        var out: [GridColumn<R>] = order.compactMap { byId[$0] }
        if let n = columns.first(where: { $0.isIndex }), !order.contains(n.id) { out.insert(n, at: 0) }   // saved layouts may predate S.No
        let have = Set(out.map { $0.id })
        out += columns.filter { !have.contains($0.id) }
        return out
    }

    func isHidden<R>(_ c: GridColumn<R>) -> Bool { touched ? hidden.contains(c.id) : c.hiddenByDefault }

    func materialise<R>(_ columns: [GridColumn<R>]) {
        if !touched {
            hidden = Set(columns.filter { $0.hiddenByDefault }.map { $0.id })
            order = columns.map { $0.id }
            touched = true
        }
    }

    func toggle<R>(_ c: GridColumn<R>, _ columns: [GridColumn<R>]) {
        materialise(columns)
        let visibleCount = ordered(columns).filter { !isHidden($0) }.count
        if hidden.contains(c.id) { hidden.remove(c.id) } else if visibleCount > 1 { hidden.insert(c.id) }
        save()
    }

    func move<R>(_ from: IndexSet, _ to: Int, _ columns: [GridColumn<R>]) {
        materialise(columns)
        var ids = ordered(columns).map { $0.id }
        ids.move(fromOffsets: from, toOffset: to)
        order = ids
        save()
    }
}
