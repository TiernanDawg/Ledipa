import Foundation
import Combine

/// Runs reliable foreground fades. iOS can suspend a normal app, so these
/// routines deliberately report that they require the app to remain open.
@MainActor final class TimerCenter: ObservableObject {
    @Published var sleepMinutes = 30.0
    @Published var wakeMinutes = 20.0
    @Published var scheduledTime = Date()
    @Published private(set) var enabled = false
    @Published private(set) var message = "Timers run while Morg’s LED is open."

    private var task: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        sleepMinutes = defaults.object(forKey: "morgs.timer.sleep") as? Double ?? 30
        wakeMinutes = defaults.object(forKey: "morgs.timer.wake") as? Double ?? 20
        if let date = defaults.object(forKey: "morgs.timer.wakeDate") as? Date { scheduledTime = date }
    }

    func sleepFade(brightness: @escaping (Double) -> Void, powerOff: @escaping () -> Void) {
        task?.cancel()
        defaults.set(sleepMinutes, forKey: "morgs.timer.sleep")
        enabled = true
        message = "Sleep fade running"
        let duration = max(1, sleepMinutes) * 60
        task = Task { @MainActor in
            let steps = 60
            for step in stride(from: steps, through: 0, by: -1) {
                if Task.isCancelled { return }
                brightness(Double(step) / Double(steps) * 100)
                do { try await Task.sleep(for: .seconds(duration / Double(steps))) }
                catch { return }
            }
            powerOff()
            enabled = false
            message = "Sleep fade completed"
            task = nil
        }
    }

    func scheduleWake(at date: Date, brightness: @escaping (Double) -> Void, powerOn: @escaping () -> Void) {
        task?.cancel()
        scheduledTime = date
        defaults.set(date, forKey: "morgs.timer.wakeDate")
        defaults.set(wakeMinutes, forKey: "morgs.timer.wake")
        let target = date > Date() ? date : Calendar.current.nextDate(after: Date(), matching: Calendar.current.dateComponents([.hour, .minute], from: date), matchingPolicy: .nextTime) ?? date
        enabled = true
        message = "Wake-up scheduled for \(target.formatted(date: .omitted, time: .shortened)) · keep the app open"
        let duration = max(1, wakeMinutes) * 60
        task = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(max(0, target.timeIntervalSinceNow))) }
            catch { return }
            if Task.isCancelled { return }
            powerOn()
            let steps = 60
            for step in 0...steps {
                if Task.isCancelled { return }
                brightness(Double(step) / Double(steps) * 100)
                do { try await Task.sleep(for: .seconds(duration / Double(steps))) }
                catch { return }
            }
            enabled = false
            message = "Sunrise wake-up completed"
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        enabled = false
        message = "Timer cancelled"
    }
}
