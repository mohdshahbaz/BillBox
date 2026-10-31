import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Works out an item's category from its name (backend/src/services/category.js).
///   1. keyword rules (instant, offline, tuned for Indian FMCG names)
///   2. when no rule fits: the free Open Food Facts product database (4 second limit, never blocks saving)
/// Results are remembered per brand + product words while the app runs.
public enum Category {
    static let RULES: [(String, JSRegex)] = [
        ("Namkeen & Snacks", rx("\\b(all\\s*time\\s*mix|bikano|namkeen|bhujia|mixture|mixt|chips|wafer|papad|kurkure|puffs?|chakli|sev|moong\\s*dal|peanut|katori|ringz?|cheese\\s*ball|munchy|crunchy|nachos|popcorn|chivda|aloo|khatta\\s*meetha|lachha|navratan|tadka|chatax|snack)", "i")),
        ("Biscuits & Cookies", rx("\\b(biscuit|cookie|cracker|rusk|marie|glucose|bourbon|cream\\s*roll)", "i")),
        ("Noodles & Pasta", rx("\\b(noodle|maggi|pasta|macaroni|vermicelli|yippee|chowmein)", "i")),
        ("Beverages", rx("\\b(cola|pepsi|coke|soda|juice|drink|water|lemonade|energy|squash|sharbat|tea|coffee|frooti|maaza|slice|sprite|fanta|thums)", "i")),
        ("Dairy", rx("\\b(milk|curd|dahi|paneer|butter|cheese|ghee|cream|lassi|buttermilk)", "i")),
        ("Chocolates & Confectionery", rx("\\b(chocolate|candy|toffee|lollipop|gum|mint|eclairs?|jelly|cadbury|dairy\\s*milk|kitkat)", "i")),
        ("Staples & Grains", rx("\\b(rice|atta|flour|maida|suji|rava|dal\\b|pulses?|poha|besan|sugar|salt|wheat|oats|cornflakes?|muesli)", "i")),
        ("Oils & Ghee", rx("\\b(oil|refined|mustard\\s*oil|sunflower|vanaspati)", "i")),
        ("Spices & Masala", rx("\\b(masala|spice|turmeric|haldi|chilli|mirch|jeera|coriander|dhaniya|garam)", "i")),
        ("Sauces & Spreads", rx("\\b(ketchup|sauce|jam|mayonnaise|spread|pickle|achar|vinegar|chutney)", "i")),
        ("Personal Care", rx("\\b(soap|shampoo|toothpaste|toothbrush|face\\s*wash|cream|lotion|deodorant|deo|talc|powder|hair|razor|sanitary|napkin|facewash|oil\\s*hair|conditioner|handwash)", "i")),
        ("Home Care", rx("\\b(detergent|dishwash|cleaner|phenyl|bleach|harpic|vim|surf|ariel|rin\\b|wheel|floor|toilet|mop|scrub|freshener|agarbatti|incense|mosquito|coil)", "i")),
        ("Stationery & General", rx("\\b(pen|pencil|notebook|battery|bulb|candle|match)", "i")),
    ]

    /// Items that must always sit in a given category, whatever else their name matches.
    static let PINNED: [(JSRegex, String)] = [(rx("all\\s*time\\s*mix", "i"), "Namkeen & Snacks")]

    public static func pinned(_ name: String?) -> String? {
        for (re, cat) in PINNED where re.test(name ?? "") { return cat }
        return nil
    }

    /// Offline switch for tests; the app keeps it on.
    public static var internetAllowed = true
    private static var cache: [String: (String?, String?)] = [:]
    private static let cacheLock = NSLock()

    /// Remove size, MRP, bracket and punctuation noise: "BIKANO CHIPS (1X144 PKT) MRP-10/-" -> "bikano chips"
    public static func cleanQuery(_ name: String?) -> String {
        var s = name ?? ""
        s = rx("\\(.*?\\)", "g").replace(s, " ")
        s = rx("\\bMRP\\b.*$", "i").replace(s, " ")
        s = rx("\\d+\\s*[xX*]\\s*\\d+", "g").replace(s, " ")
        s = rx("\\b\\d+(\\.\\d+)?\\s*(g|gm|kg|ml|ltr|l|pkt|pcs)\\b", "gi").replace(s, " ")
        s = rx("[^A-Za-z ]+", "g").replace(s, " ")
        s = rx("\\s+", "g").replace(s, " ")
        return JS.trim(s).lowercased()
    }

    public static func byRules(_ text: String) -> String? {
        for (cat, re) in RULES where re.test(text) { return cat }
        return nil
    }

    static func fromInternet(_ query: String) async -> String? {
        guard !query.isEmpty, internetAllowed else { return nil }
        let url = "https://world.openfoodfacts.org/cgi/search.pl?search_simple=1&action=process&json=1&page_size=6&fields=product_name,categories&search_terms="
            + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? query)
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 4)
        req.setValue("DistributorPro/3 (local desktop app)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await fetch(req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let cats = ((j["products"] as? [Any]) ?? []).compactMap { p -> String? in
                let c = JS.string(((p as? [String: Any])?["categories"]).flatMap { unwrap($0) } ?? "")
                return c.isEmpty || c == "undefined" ? nil : c
            }
            if cats.isEmpty { return nil }
            for c in cats { if let m = byRules(c) { return m } }                 // map the database's wording to our category names
            let first = cats[0].components(separatedBy: ",").map { JS.trim($0) }.filter { !$0.isEmpty }.first
            guard let f = first else { return nil }
            return rx("^[a-z]{2}:", "i").replace(f, "").jsSlice(0, 40)
        } catch { return nil }                                                // offline or slow: just no suggestion
    }

    private static func fetch(_ req: URLRequest) async throws -> (Data, URLResponse?) {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<(Data, URLResponse?), Error>) in
            URLSession.shared.dataTask(with: req) { d, r, e in
                if let e { c.resume(throwing: e) } else { c.resume(returning: (d ?? Data(), r)) }
            }.resume()
        }
    }

    private static func cached(_ key: String) -> (String?, String?)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }
    private static func remember(_ key: String, _ v: (String?, String?)) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache[key] = v
    }

    /// -> (name, "rules" | "internet") or (nil, nil)
    public static func guess(_ itemName: String, online: Bool = true) async -> (name: String?, source: String?) {
        if let pin = pinned(itemName) { return (pin, "rules") }
        let q = cleanQuery(itemName)
        let key = q.components(separatedBy: " ").prefix(3).joined(separator: " ")
        if let hit = cached(key) { return hit }
        var out: (String?, String?) = (byRules(itemName) ?? byRules(q), "rules")
        if out.0 == nil && online {
            let n = await fromInternet(q)
            out = n != nil ? (n, "internet") : (nil, nil)
        }
        if out.0 == nil { out = (nil, nil) }
        if out.0 != nil { remember(key, out) }
        return out
    }

    /// Existing category with that name (any case), or a new one. Returns its id.
    static func ensure(_ db: Database, _ name: String?) throws -> Int? {
        guard let name, !name.isEmpty else { return nil }
        if let row = try db.prepare("SELECT id FROM categories WHERE lower(name)=lower(?)").get(name) { return row.i("id") }
        return try db.prepare("INSERT INTO categories(name) VALUES(?)").run(name).lastInsertRowid
    }
}
