import Foundation
import BillBoxCore
import ParityKit

// Parity runner: executes a scenario (a JSON array of steps, see ParityRunner) against BillBoxCore and prints one JSON line per step.
//   bbcheck <data-dir> <scenario.json> [backup-dir]

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
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
