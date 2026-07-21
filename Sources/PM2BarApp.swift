import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarDelegate = PM2MenuBarDelegate()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarDelegate.start()
    }
}

@main
struct PM2BarApp {
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        app.delegate = appDelegate
        app.run()
    }
}
