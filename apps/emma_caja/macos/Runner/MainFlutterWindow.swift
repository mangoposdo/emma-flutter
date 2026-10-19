import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Sin restaurar la ventana anterior: macOS pondría encima su tamaño.
    // El título sale de PRODUCT_NAME (Configs/AppInfo.xcconfig).
    self.isRestorable = false
    // Abre maximizada, como la caja de la 0.7 (WindowState="Maximized").
    self.contentMinSize = NSSize(width: 800, height: 560)
    if let pantalla = NSScreen.main {
      self.setFrame(pantalla.visibleFrame, display: true)
    } else {
      self.setContentSize(NSSize(width: 1280, height: 800))
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
