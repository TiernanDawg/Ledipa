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

    func sleepFade(startingAt currentBrightness: Double = 100, brightness: @escaping (Double) -> Void, powerOff: @escaping () -> Void) {
        cancel(updateMessage: false)
        defaults.set(sleepMinutes, forKey: "morgs.timer.sleep")
        enabled = true
        message = "Sleep fade running"
        let duration = min(720, max(1, sleepMinutes)) * 60
        task = Task { @MainActor in
            let steps = 60
            for step in stride(from: steps, through: 0, by: -1) {
                if Task.isCancelled { return }
                brightness(max(0, min(100, currentBrightness)) * Double(step) / Double(steps))
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
        cancel(updateMessage: false)
        scheduledTime = date
        defaults.set(date, forKey: "morgs.timer.wakeDate")
        defaults.set(wakeMinutes, forKey: "morgs.timer.wake")
        let now = Date()
        let target: Date
        if date > now {
            target = date
        } else {
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            target = Calendar.current.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
                ?? Calendar.current.date(byAdding: .day, value: 1, to: date)
                ?? now.addingTimeInterval(24 * 60 * 60)
        }
        enabled = true
        message = "Wake-up scheduled for \(target.formatted(date: .omitted, time: .shortened)) · keep the app open"
        let duration = min(720, max(1, wakeMinutes)) * 60
        task = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(max(0, target.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
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

    func cancel(updateMessage: Bool = true) {
        task?.cancel()
        task = nil
        enabled = false
        if updateMessage { message = "Timer cancelled" }
    }
}
