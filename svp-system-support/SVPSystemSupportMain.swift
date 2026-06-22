import AppKit

@main
struct SVPSystemSupportMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = SVPSystemSupportApp()

        application.delegate = delegate
        application.servicesProvider = delegate
        application.run()
    }
}
