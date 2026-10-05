import Foundation
let service = AudioDeviceService()
let iterations = Int(CommandLine.arguments.dropFirst().first ?? "200") ?? 200
let start = DispatchTime.now().uptimeNanoseconds
var count = 0
for _ in 0..<iterations { count += service.getDevices().count }
for device in service.getDevices() {
    print("\(device.id)|\(device.uid)|\(device.name)|\(device.type.rawValue)|\(device.isConnected)|\(device.batteryLevel.map(String.init) ?? "nil")|\(device.isBuiltIn)")
}
fputs("elapsed_ns=\(DispatchTime.now().uptimeNanoseconds - start)\n", stderr)
