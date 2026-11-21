import Flutter
import UIKit

final class AwesunBridge {
    static let shared = AwesunBridge()

    private var channel: FlutterMethodChannel?

    private init() {}

    func attach(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func command(_ id: String, _ arguments: [String: Any] = [:],
                 completion: FlutterResult? = nil) {
        var values = arguments
        values["id"] = id
        channel?.invokeMethod("command", arguments: values, result: completion)
    }

    func virtualClick(_ button: String, at point: CGPoint?) {
        var args: [String: Any] = ["button": button]
        if let point = point {
            args["x"] = Double(point.x)
            args["y"] = Double(point.y)
        }
        channel?.invokeMethod("virtualClick", arguments: args)
    }

    func virtualMove(to point: CGPoint, canvasDelta: CGSize = .zero) {
        channel?.invokeMethod("virtualMove", arguments: [
            "x": Double(point.x), "y": Double(point.y),
            "panX": Double(canvasDelta.width), "panY": Double(canvasDelta.height)
        ])
    }

    func virtualDrag(_ down: Bool, at point: CGPoint? = nil) {
        var args: [String: Any] = ["down": down]
        if let point = point {
            args["x"] = Double(point.x)
            args["y"] = Double(point.y)
        }
        channel?.invokeMethod("virtualDrag", arguments: args)
    }

    func scroll(_ steps: Int, at point: CGPoint?) {
        var args: [String: Any] = ["dy": steps]
        if let point = point {
            args["x"] = Double(point.x)
            args["y"] = Double(point.y)
        }
        channel?.invokeMethod("scroll", arguments: args)
    }

    func pointerVisible(_ visible: Bool) {
        channel?.invokeMethod("virtualPointerVisible", arguments: ["visible": visible])
    }

    func key(_ name: String, down: Bool) {
        channel?.invokeMethod("key", arguments: ["name": name, "down": down])
    }

    func closeSession() {
        channel?.invokeMethod("close", arguments: nil)
    }
}
