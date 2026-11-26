import AppKit
import Combine

enum Mode: String, CaseIterable, Identifiable {
    case breathe, steady, automatic, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .breathe: return "Respiration"
        case .steady: return "Fixe"
        case .automatic: return "macOS"
        case .off: return "Éteint"
        }
    }
}

@MainActor
final class Engine: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: Réglages (sauvegardés)

    @Published var mode: Mode {
        didSet { defaults.set(mode.rawValue, forKey: "mode"); modeChanged(from: oldValue) }
    }
    /// Luminosité max (respiration) ou luminosité fixe, 0 à 1.
    @Published var maxLevel: Double {
        didSet {
            defaults.set(maxLevel, forKey: "maxLevel")
            if minLevel > maxLevel - 0.05 { minLevel = max(0, maxLevel - 0.05) }
            restartEffect()
        }
    }
    /// Luminosité min de la respiration, 0 à 1.
    @Published var minLevel: Double {
        didSet { defaults.set(minLevel, forKey: "minLevel") }
    }
    /// Durée d'une respiration complète (secondes).
    @Published var period: Double {
        didSet { defaults.set(period, forKey: "period") }
    }
    /// Allumer le logo capot fermé, uniquement si le Mac est éveillé.
    @Published var glowWhenClosed: Bool {
        didSet { defaults.set(glowWhenClosed, forKey: "glowWhenClosed"); slowTick() }
    }

    /// Sur batterie : rendre complètement la main à macOS (aucun effet, pas d'allumage capot fermé).
    @Published var automaticOnBattery: Bool {
        didSet { defaults.set(automaticOnBattery, forKey: "automaticOnBattery"); slowTick() }
    }

    @Published private(set) var status = "Démarrage…"

    // MARK: Interne

    private let emitter = LightEmitter()
    private var slowTimer: Timer?
    /// Minuterie ponctuelle : prochaine inversion de la respiration, ou moment de figer en mode Fixe.
    private var stepTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private var systemAsleep = false
    private var screensAsleep = false
    private var lidOverridden = false
    private var effectsRunning = false
    private var rising = true
    private var firstStep = true

    init() {
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .breathe
        maxLevel = defaults.object(forKey: "maxLevel") as? Double ?? 0.8
        minLevel = defaults.object(forKey: "minLevel") as? Double ?? 0.1
        period = defaults.object(forKey: "period") as? Double ?? 6
        glowWhenClosed = defaults.object(forKey: "glowWhenClosed") as? Bool ?? true
        automaticOnBattery = defaults.object(forKey: "automaticOnBattery") as? Bool ?? true
    }

    func start() {
        guard let e = emitter else {
            status = "API du logo introuvable sur ce Mac."
            return
        }
        e.set(LightEmitter.Key.backlightMode, mode == .off ? 0 : 2)

        let center = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ block: @escaping @MainActor () -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { block() }
            })
        }
        on(NSWorkspace.willSleepNotification) { [weak self] in self?.systemAsleep = true; self?.pauseAll() }
        on(NSWorkspace.didWakeNotification) { [weak self] in self?.systemAsleep = false; self?.slowTick() }
        on(NSWorkspace.screensDidSleepNotification) { [weak self] in self?.screensAsleep = true; self?.pauseAll() }
        on(NSWorkspace.screensDidWakeNotification) { [weak self] in self?.screensAsleep = false; self?.slowTick() }

        // Surveillance légère du capot et de la chauffe.
        slowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.slowTick() }
        }
        slowTimer?.tolerance = 0.5 // laisse macOS regrouper les réveils
        slowTick()
    }

    func shutdown() {
        stopEffects()
        if lidOverridden { emitter?.endLidOverride(); lidOverridden = false }
    }

    // MARK: Logique (1 fois par seconde)

    func slowTick() {
        guard let e = emitter else { return }

        let lidClosed = SystemMonitor.isLidClosed()
        let hot = SystemMonitor.isHot
        let awake = !systemAsleep && !screensAsleep
        let battery = SystemMonitor.isOnBattery
        let handBack = automaticOnBattery && battery // sur batterie : comportement d'origine

        if lidClosed {
            // Capot fermé : allumé seulement si le Mac (et son écran) est éveillé.
            let want = glowWhenClosed && awake && !hot && !handBack && mode != .off
            if want && !lidOverridden {
                e.overrideLid(externalDisplays: SystemMonitor.externalDisplays())
                lidOverridden = true
                restartEffect()
            } else if !want && lidOverridden {
                stopEffects()
                e.endLidOverride()
                lidOverridden = false
            }
        } else {
            lidOverridden = false // à l'ouverture, macOS repasse lui-même en "capot ouvert"
        }

        let shouldRun = awake && !hot && !handBack
            && (mode == .breathe || mode == .steady)
            && (!lidClosed || lidOverridden)
        if shouldRun && !effectsRunning {
            effectsRunning = true
            restartEffect()
        } else if !shouldRun {
            stopEffects()
        }

        status = makeStatus(lidClosed: lidClosed, hot: hot, handBack: handBack)
    }

    // MARK: Effets (un réveil par étape, sans suivi continu)

    private func restartEffect() {
        stepTimer?.invalidate()
        stepTimer = nil
        firstStep = true
        guard effectsRunning else { return }
        step()
    }

    private func step() {
        guard effectsRunning, let e = emitter else { return }
        switch mode {
        case .breathe: breatheStep(e)
        case .steady: steadyStep(e)
        default: break
        }
    }

    /// Une demi-respiration : on lit le niveau une fois, on lance le fondu,
    /// et on programme l'inversion au moment où le niveau atteindra sa cible.
    private func breatheStep(_ e: LightEmitter) {
        let f = e.factor ?? (rising ? minLevel : maxLevel)
        let up = firstStep ? (f < maxLevel - 0.02) : !rising
        firstStep = false
        rising = up

        let half = period / 2
        let target = up ? maxLevel : minLevel
        let total = up ? 1 - f : f                       // trajet complet du fondu (jusqu'à 1 ou 0)
        let dist = max(0, up ? target - f : f - target)  // trajet voulu
        if total > 0.01, dist > 0.01 {
            let s = Self.springTime(forProgress: dist / total)
            e.fade(to: up ? .unblank : .blank, duration: half / max(s, 0.05))
        }
        schedule(after: half) { [weak self] in self?.step() }
    }

    /// Mode Fixe : un fondu vers la luminosité voulue, puis on fige au bon moment.
    private func steadyStep(_ e: LightEmitter) {
        guard let f = e.factor else { return }
        let dist = maxLevel - f
        if abs(dist) < 0.02 { e.hold(); return }
        let up = dist > 0
        let total = up ? 1 - f : f
        let s = Self.springTime(forProgress: abs(dist) / max(total, 0.01))
        let duration = 1.2
        e.fade(to: up ? .unblank : .blank, duration: duration)
        schedule(after: s * duration) { [weak self] in
            guard let self, self.effectsRunning, self.mode == .steady else { return }
            self.emitter?.hold()
        }
    }

    private func schedule(after delay: Double, _ action: @escaping @MainActor () -> Void) {
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, delay), repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        stepTimer?.tolerance = 0.03
    }

    /// Courbe des fondus du daemon (ressort amorti, mesurée par LogoLight) :
    /// p(s) = 1 - (1 + k·s)·e^(-k·s), k = 6,51, s = fraction de la durée écoulée.
    /// Renvoie la fraction s nécessaire pour parcourir la fraction p du trajet.
    private static func springTime(forProgress p: Double) -> Double {
        let k = 6.51
        func curve(_ s: Double) -> Double { 1 - (1 + k * s) * exp(-k * s) }
        let target = min(max(p, 0), curve(1))
        var lo = 0.0, hi = 1.0
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            if curve(mid) < target { lo = mid } else { hi = mid }
        }
        return hi
    }

    // MARK: Aides

    private func stopEffects() {
        stepTimer?.invalidate()
        stepTimer = nil
        guard effectsRunning else { return }
        effectsRunning = false
        firstStep = true
        emitter?.restore()
    }

    private func pauseAll() {
        stopEffects()
        if lidOverridden { emitter?.endLidOverride(); lidOverridden = false }
    }

    private func modeChanged(from old: Mode) {
        stopEffects()
        if mode == .off { emitter?.set(LightEmitter.Key.backlightMode, 0) }
        else if old == .off { emitter?.set(LightEmitter.Key.backlightMode, 2) }
        slowTick()
    }

    private func makeStatus(lidClosed: Bool, hot: Bool, handBack: Bool) -> String {
        if handBack && mode != .off { return "Sur batterie : comportement macOS" }
        var parts: [String] = []
        if mode == .breathe { parts.append(String(format: "Respiration %.1f s", period)) }
        if lidClosed { parts.append(lidOverridden ? "capot fermé : logo actif" : "capot fermé : logo éteint") }
        if hot { parts.append("Mac chaud : effets coupés") }
        return parts.isEmpty ? "Prêt" : parts.joined(separator: " · ")
    }
}
