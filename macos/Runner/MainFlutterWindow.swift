import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "MultiPad"

    // Modern hidden title bar styling & full size content view
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    if let appDelegate = NSApp.delegate as? AppDelegate {
      self.delegate = appDelegate
      appDelegate.attachMethodChannel(viewController: flutterViewController, window: self)
    }

    super.awakeFromNib()
  }
}
