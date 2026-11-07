import Foundation
import BillBoxCore
import ParityKit

// Parity runner: executes a scenario (a JSON array of steps, see ParityRunner) against BillBoxCore and prints one JSON line per step.
//   bbcheck <data-dir> <scenario.json> [backup-dir]

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments

// Live sync test (backend/test/sync_swift.js): bbcheck --serve <data-dir> answers one JSON request per stdin line,
//   {"id","method","path","body","company"} → {"id","status","body"};  {"id","sql","args","company"} → rows of that company
if args.count >= 3 && args[1] == "--serve" {
    let env = ProcessInfo.processInfo.environment
    if let v = env["BILLBOX_FIREBASE_DB"] { Sync.databaseURL = v }
    if let v = env["BILLBOX_FIREBASE_AUTH"] { Sync.authURL = v }
    if let v = env["BILLBOX_FIREBASE_TOKEN"] { Sync.tokenURL = v }
    if let v = env["BILLBOX_FIREBASE_KEY"] { Sync.apiKey = v }
    let router = try Router(dataDir: args[2])
    let done = DispatchSemaphore(value: 0)
    Task {
        while let line = readLine() {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let id = o["id"] ?? 0
            let company: Int? = (o["company"] as? Int) ?? (o["company"] as? Double).map { Int($0) }
            var out: [String: Any] = ["id": id]
            if let sql = o["sql"] as? String {
                do {
                    let rows: [Row] = try await router.exclusive {
                        let d = try router.engine.openCompany(company ?? (try router.engine.firstCompanyId() ?? 0))!
                        let st = d.prepare(sql)
                        let a = (o["args"] as? [Any]) ?? []
                        if sql.uppercased().hasPrefix("SELECT") { return try a.isEmpty ? st.all() : (a.count == 1 ? st.all(a[0]) : st.all(a[0], a[1])) }
                        try st.runArgs(a); return []
                    }
                    out["status"] = 200; out["body"] = rows.map { r in r.mapValues { $0 is NSNull ? NSNull() : $0 } }
                } catch { out["status"] = 500; out["body"] = ["error": "\(error)"] }
            } else {
                let r = await router.handle(o["method"] as? String ?? "GET", o["path"] as? String ?? "/", body: (o["body"] as? [String: Any]) ?? [:], companyId: company)
                if case .json(let st, let v) = r { out["status"] = st; out["body"] = v }
            }
            print(String(data: try! JSONSerialization.data(withJSONObject: JSONNorm.normalize(out) as Any, options: [.fragmentsAllowed]), encoding: .utf8)!)
        }
        done.signal()
    }
    done.wait()
    exit(0)
}
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: bbcheck <data-dir> <scenario.json> [backup-dir]\n".data(using: .utf8)!)
    exit(2)
}
Category.internetAllowed = false
if args.count >= 4 { Backup.defaultDir = args[3] }
let runner = ParityRunner(router: try Router(dataDir: args[1]))
let steps = (JSONNorm.normalize(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2])))) as! [Any]).map { $0 as! [String: Any] }

let sem = DispatchSemaphore(value: 0)
Task {
    await runner.run(steps) { print(try! JSONText.compact($0)) }
    sem.signal()
}
sem.wait()
