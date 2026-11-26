import Foundation
import CoreGraphics

/// Accès à l'API privée CoreBrightness qui pilote la LED du logo
/// (module "LE" = light emitter du daemon corebrightnessd).
/// Clés et comportements documentés par le projet LogoLight (MIT) :
/// https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md
/// API non officielle : une mise à jour de macOS peut la casser.
final class LightEmitter {
    enum State: Int {
        case blank = 1    // fondu vers éteint
        case unblank = 2  // fondu vers allumé
        var opposite: State { self == .blank ? .unblank : .blank }
    }

    enum Key {
        static let backlightMode = "LEBacklightMode"        // 0 éteint, 2 allumé (persistant)
        static let fadeDuration = "LEPWMFactorFadeDuration" // secondes, 0 = automatique
        static let logicalState = "DisplayLogicalState"     // 1 Blank, 2 Unblank
        static let pwmState = "LEPWMState"                  // lecture seule, contient "Factor"
        static let clamshell = "ClamshellUpdate"            // 0 capot ouvert, 1 capot fermé
    }

    private typealias CopyFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias SetFn = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Bool
    private typealias SetWithIDFn = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool
    private typealias CopyIDsFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

    private static let copySel = NSSelectorFromString("copyPropertyForKey:")
    private static let setSel = NSSelectorFromString("setProperty:forKey:")
    private static let displaySel = NSSelectorFromString("setProperty:withKey:andDisplay:")
    private static let keyboardSel = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private static let keyboardIDsSel = NSSelectorFromString("copyKeyboardBacklightIDs")

    private let client: NSObject
    private let copyFn: CopyFn
    private let setFn: SetFn
    private let setDisplayFn: SetWithIDFn?
    private let setKeyboardFn: SetWithIDFn?
    private let keyboardIDs: [UInt64]

    /// Dernier état écrit (le daemon ignore l'écriture de l'état déjà en cours).
    private(set) var lastState: State = .unblank

    init?() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              type.instancesRespond(to: Self.copySel),
              type.instancesRespond(to: Self.setSel)
        else { return nil }

        let c = type.init()
        client = c
        copyFn = unsafeBitCast(c.method(for: Self.copySel), to: CopyFn.self)
        setFn = unsafeBitCast(c.method(for: Self.setSel), to: SetFn.self)
        setDisplayFn = type.instancesRespond(to: Self.displaySel)
            ? unsafeBitCast(c.method(for: Self.displaySel), to: SetWithIDFn.self) : nil
        setKeyboardFn = type.instancesRespond(to: Self.keyboardSel)
            ? unsafeBitCast(c.method(for: Self.keyboardSel), to: SetWithIDFn.self) : nil

        var ids: [UInt64] = []
        if let kType = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
           kType.instancesRespond(to: Self.keyboardIDsSel) {
            let k = kType.init()
            let f = unsafeBitCast(k.method(for: Self.keyboardIDsSel), to: CopyIDsFn.self)
            if let arr = f(k, Self.keyboardIDsSel)?.takeRetainedValue() as? [NSNumber] {
                ids = arr.map { $0.uint64Value }
            }
        }
        keyboardIDs = ids
    }

    // MARK: Accès bas niveau

    func value(_ key: String) -> Any? {
        copyFn(client, Self.copySel, key as NSString)?.takeRetainedValue()
    }

    @discardableResult
    func set(_ key: String, _ value: Double) -> Bool {
        setFn(client, Self.setSel, NSNumber(value: value), key as NSString)
    }

    private func setForDisplays(_ key: String, _ value: Double, ids: [CGDirectDisplayID]) {
        guard let f = setDisplayFn else { return }
        for id in ids { _ = f(client, Self.displaySel, NSNumber(value: value), key as NSString, UInt64(id)) }
    }

    private func setForKeyboards(_ key: String, _ value: Double) {
        guard let f = setKeyboardFn else { return }
        for id in keyboardIDs { _ = f(client, Self.keyboardSel, NSNumber(value: value), key as NSString, id) }
    }

    /// Niveau actuel du logo, de 0 à 1.
    var factor: Double? {
        guard let dict = value(Key.pwmState) as? [String: Any] else { return nil }
        return (dict["Factor"] as? NSNumber)?.doubleValue
    }

    // MARK: Fondus

    /// Lance un fondu vers allumé (1) ou éteint (0). La durée couvre tout le trajet
    /// du niveau actuel jusqu'à 0 ou 1.
    func fade(to state: State, duration: Double) {
        if state == lastState {
            // Écrire le même état serait ignoré : on passe d'abord par l'état opposé
            // avec une durée énorme (le niveau ne bouge quasiment pas).
            set(Key.fadeDuration, 1e9)
            set(Key.logicalState, Double(state.opposite.rawValue))
        }
        set(Key.fadeDuration, max(0.05, duration))
        set(Key.logicalState, Double(state.rawValue))
        lastState = state
    }

    /// Fige le niveau actuel (fondu inverse d'une durée quasi infinie).
    func hold() {
        set(Key.fadeDuration, 1e9)
        let o = lastState.opposite
        set(Key.logicalState, Double(o.rawValue))
        lastState = o
    }

    /// Rend la main au comportement automatique de macOS.
    func restore() {
        set(Key.fadeDuration, 0)
        if lastState == .unblank { set(Key.logicalState, Double(State.blank.rawValue)) }
        set(Key.logicalState, Double(State.unblank.rawValue))
        lastState = .unblank
    }

    // MARK: Capot fermé

    /// Fait croire au module du logo que le capot est ouvert, tout en gardant
    /// le clavier et les écrans externes en mode "capot fermé"
    /// (sinon True Tone peut teinter les écrans externes).
    func overrideLid(externalDisplays: [CGDirectDisplayID]) {
        set(Key.clamshell, 0)
        setForKeyboards(Key.clamshell, 1)
        setForDisplays(Key.clamshell, 1, ids: externalDisplays)
    }

    func endLidOverride() {
        set(Key.clamshell, 1)
    }
}
