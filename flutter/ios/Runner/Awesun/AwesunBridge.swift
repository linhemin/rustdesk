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

    func virtualClick(_ button: String) {
        channel?.invokeMethod("virtualClick", arguments: ["button": button])
    }

    func virtualPosition(_ point: CGPoint) {
        channel?.invokeMethod("virtualPosition", arguments: ["x": Double(point.x), "y": Double(point.y)])
    }

    func virtualDrag(_ down: Bool) {
        channel?.invokeMethod("virtualDrag", arguments: ["down": down])
    }

    func scroll(_ steps: Int) {
        channel?.invokeMethod("scroll", arguments: ["dy": steps])
    }

    func key(_ name: String, down: Bool) {
        channel?.invokeMethod("key", arguments: ["name": name, "down": down])
    }

    func closeSession() {
        channel?.invokeMethod("close", arguments: nil)
    }
}
