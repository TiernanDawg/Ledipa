import Foundation
import UserNotifications

@MainActor final class TimerCenter: ObservableObject {
    @Published var sleepMinutes = 30.0
    @Published var wakeMinutes = 20.0
    @Published var scheduledTime = Date()
    @Published var enabled = false
    @Published var message = "Schedules run while Morg’s LED is open. iOS may suspend Bluetooth work in the background."
    private var task: Task<Void,Never>?

    func sleepFade(brightness: @escaping (Double)->Void, powerOff: @escaping ()->Void) {
        task?.cancel()
        let duration = max(1, sleepMinutes) * 60
        task = Task { @MainActor in
            let steps = 60
            for step in stride(from: steps, through: 0, by: -1) {
                if Task.isCancelled { return }
                brightness(Double(step)/Double(steps)*100)
                try? await Task.sleep(for: .seconds(duration/Double(steps)))
            }
            powerOff()
            message = "Sleep fade completed"
        }
    }
    func cancel() { task?.cancel(); task=nil; message="Timer cancelled" }
}
