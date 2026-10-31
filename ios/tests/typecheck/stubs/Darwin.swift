// Type-check stub (Linux only): Darwin is Glibc plus the BSD pieces BillBox uses.
@_exported import Glibc
public struct extern_proc { public var p_flag: Int32 = 0 }
public struct kinfo_proc { public var kp_proc = extern_proc(); public init() {} }
public let CTL_KERN: Int32 = 1, KERN_PROC: Int32 = 14, KERN_PROC_PID: Int32 = 1, P_TRACED: Int32 = 0x800
public func sysctl(_ name: UnsafeMutablePointer<Int32>!, _ namelen: UInt32, _ oldp: UnsafeMutableRawPointer!, _ oldlenp: UnsafeMutablePointer<Int>!, _ newp: UnsafeMutableRawPointer!, _ newlen: Int) -> Int32 { 0 }
