import Foundation
import IOKit
import IOKit.storage
import IOKit.usb

class USBManager: ObservableObject {
    @Published var availableDevices: [USBDevice] = []
    
    struct USBDevice: Identifiable, Equatable {
        let id = UUID()
        let identifier: String
        let name: String
        let size: String
        let devicePath: String
        let isRemovable: Bool
        
        static func == (lhs: USBDevice, rhs: USBDevice) -> Bool {
            lhs.identifier == rhs.identifier
        }
    }
    
    init() {
        refreshDevices()
    }
    
    func refreshDevices() {
        availableDevices = getUSBDevices()
    }
    
    private func getUSBDevices() -> [USBDevice] {
        var devices: [USBDevice] = []
        
        // Get all mounted volumes
        let fileManager = FileManager.default
        let mountedVolumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeTotalCapacityKey
        ])
        
        for volumeURL in mountedVolumes ?? [] {
            do {
                let resourceValues = try volumeURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeIsRemovableKey,
                    .volumeIsEjectableKey,
                    .volumeTotalCapacityKey
                ])
                
                guard let isRemovable = resourceValues.volumeIsRemovable,
                      let isEjectable = resourceValues.volumeIsEjectable,
                      (isRemovable || isEjectable) else {
                    continue
                }
                
                let name = resourceValues.volumeName ?? "Unknown Device"
                let capacity = resourceValues.volumeTotalCapacity ?? 0
                let size = ByteCountFormatter.string(fromByteCount: Int64(capacity), countStyle: .file)
                let devicePath = volumeURL.path
                let identifier = volumeURL.lastPathComponent
                
                let device = USBDevice(
                    identifier: identifier,
                    name: name,
                    size: size,
                    devicePath: devicePath,
                    isRemovable: isRemovable
                )
                
                devices.append(device)
            } catch {
                print("Error reading volume properties: \(error)")
            }
        }
        
        return devices
    }
    
    func getDeviceInfo(for device: USBDevice) -> [String: Any] {
        var info: [String: Any] = [:]
        
        do {
            let fileManager = FileManager.default
            let attributes = try fileManager.attributesOfFileSystem(forPath: device.devicePath)
            
            info["totalSize"] = attributes[.systemSize] as? NSNumber
            info["freeSize"] = attributes[.systemFreeSize] as? NSNumber
            // Note: systemFileSystemType is not available in FileAttributeKey
            // info["fileSystemType"] = attributes[.systemFileSystemType] as? String
        } catch {
            print("Error getting device info: \(error)")
        }
        
        return info
    }
    
    func unmountDevice(_ device: USBDevice) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["unmount", device.devicePath]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("Error unmounting device: \(error)")
            return false
        }
    }
    
    func mountDevice(_ device: USBDevice) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["mount", device.devicePath]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("Error mounting device: \(error)")
            return false
        }
    }
}
