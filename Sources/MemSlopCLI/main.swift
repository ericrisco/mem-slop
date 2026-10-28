import Darwin
import Foundation
import MemSlopCore

// `memslop` — the command-line side of MemSlop. Shipped inside MemSlop.app/Contents/Helpers.

let version = MemSlopVersion.current
var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "help" : arguments.removeFirst()

do {
    switch command {
    case "status": try Commands.status(arguments)
    case "ps", "list": try Commands.ps(arguments)
    case "ports": try Commands.ports(arguments)
    case "quit", "kill": exit(try await Commands.quit(arguments))
    case "hooks": exit(try Commands.hooks(arguments))
    case "hook": Commands.hook(arguments)
    case "--version", "-v", "version": print("memslop \(version)")
    case "help", "--help", "-h": print(Commands.usage)
    default:
        Terminal.error("unknown command '\(command)'")
        print(Commands.usage)
        exit(64)
    }
} catch {
    Terminal.error("\(error)")
    exit(1)
}
