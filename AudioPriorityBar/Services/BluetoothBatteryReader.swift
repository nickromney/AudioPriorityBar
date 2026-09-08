import Foundation
import IOBluetooth

/// Reads the battery percentage that macOS keeps for connected Bluetooth
/// accessories.
///
/// The current public IOBluetooth headers do not declare the battery fields
/// used by macOS for many audio accessories. They are still present on the
/// runtime `IOBluetoothDevice` object, so access them only after checking that
/// the selector exists. An unsupported device therefore simply returns nil.
final class BluetoothBatteryReader {
    func batteryLevel(for audioDevice: AudioDevice) -> Int? {
        guard audioDevice.isConnected else { return nil }

        let bluetoothDevices = (IOBluetoothDevice.pairedDevices() ?? [])
            .compactMap { $0 as? IOBluetoothDevice }
            .filter { $0.isConnected() }

        guard let bluetoothDevice = bluetoothDevices.first(where: { matches($0, audioDevice: audioDevice) }) else {
            return nil
        }

        // Generic Bluetooth headsets commonly report this value. Apple audio
        // accessories may instead use one of the other fields below.
        if let level = percentage(from: bluetoothDevice, key: "batteryPercentSingle") {
            return level
        }

        if let level = percentage(from: bluetoothDevice, key: "headsetBatteryPercent") {
            return level
        }

        if let level = percentage(from: bluetoothDevice, key: "batteryPercentCombined") {
            return level
        }

        if let level = percentage(from: bluetoothDevice, key: "batteryPercentCase") {
            return level
        }

        // HFP exposes a standard 0...5 battery indicator. This is useful for
        // headsets whose generic macOS battery fields are not populated.
        if let level = handsFreeBatteryLevel(for: bluetoothDevice) {
            return level
        }

        let left = percentage(from: bluetoothDevice, key: "batteryPercentLeft")
        let right = percentage(from: bluetoothDevice, key: "batteryPercentRight")
        if let left, let right {
            return (left + right) / 2
        }
        return left ?? right
    }

    private func handsFreeBatteryLevel(for device: IOBluetoothDevice) -> Int? {
        guard device.isHandsFreeDevice,
              let handsFreeDevice = IOBluetoothHandsFreeDevice(device: device, delegate: nil) else {
            return nil
        }

        let charge = handsFreeDevice.indicator(IOBluetoothHandsFreeIndicatorBattChg)
        guard (0...5).contains(charge) else { return nil }
        return Int((Double(charge) / 5.0 * 100.0).rounded())
    }

    private func matches(_ bluetoothDevice: IOBluetoothDevice, audioDevice: AudioDevice) -> Bool {
        let audioName = audioDevice.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !audioName.isEmpty else { return false }

        let names = [bluetoothDevice.name, bluetoothDevice.nameOrAddress]
            .compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return names.contains {
            $0.caseInsensitiveCompare(audioName) == .orderedSame
        }
    }

    private func percentage(from device: IOBluetoothDevice, key: String) -> Int? {
        let selector = NSSelectorFromString(key)
        guard device.responds(to: selector),
              let number = device.value(forKey: key) as? NSNumber else {
            return nil
        }

        let value = number.intValue
        // 255 and negative values are used by Bluetooth implementations to
        // represent an unavailable percentage.
        guard (0...100).contains(value) else { return nil }
        return value
    }
}
