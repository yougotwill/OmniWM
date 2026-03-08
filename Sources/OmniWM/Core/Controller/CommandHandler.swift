import AppKit
import Foundation

@MainActor
final class CommandHandler {
    weak var controller: WMController?

    init(controller: WMController) {
        self.controller = controller
    }

    func handleCommand(_ command: HotkeyCommand) {
        guard let controller, controller.isEnabled else { return }
        guard let controllerCommand = command.controllerCommand else {
            rejectUnmappableCommand(command)
            return
        }
        guard controller.submitControllerCommand(controllerCommand) else {
            rejectSubmissionFailure(command)
            return
        }
    }

    private func rejectUnmappableCommand(_ command: HotkeyCommand) {
        NSSound.beep()
        NSLog("No Zig controller mapping for command: %@", command.displayName)
    }

    private func rejectSubmissionFailure(_ command: HotkeyCommand) {
        NSSound.beep()
        NSLog("Zig controller rejected command: %@", command.displayName)
    }
}
