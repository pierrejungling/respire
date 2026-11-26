import Foundation
import IOKit
import IOKit.ps
import CoreGraphics

enum SystemMonitor {
    /// Capot fermé ? (propriété AppleClamshellState de IOPMrootDomain, API publique IOKit)
    static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (prop?.takeRetainedValue() as? Bool) ?? false
    }

    /// Écrans externes actifs.
    static func externalDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    }

    /// Le Mac tourne sur batterie ? (API publique IOKit Power Sources)
    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == "Battery Power"
    }

    /// Le Mac chauffe ? (état thermique signalé par macOS)
    static var isHot: Bool {
        let s = ProcessInfo.processInfo.thermalState
        return s == .serious || s == .critical
    }
}
