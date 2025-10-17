import Foundation
import AppKit

class ISOManager: ObservableObject {
    
    // MARK: - ISO to USB Operations
    
    func burnISOToUSB(isoPath: String, usbDevice: USBManager.USBDevice, progressHandler: @escaping (Double) -> Void) async throws {
        // First, unmount the USB device
        let usbManager = USBManager()
        guard usbManager.unmountDevice(usbDevice) else {
            throw ISOManagerError.deviceUnmountFailed
        }
        
        // Get the raw device identifier (e.g., /dev/disk2)
        let rawDevicePath = try await getRawDevicePath(for: usbDevice)
        
        // Verify the ISO file exists
        guard FileManager.default.fileExists(atPath: isoPath) else {
            throw ISOManagerError.isoFileNotFound
        }
        
        // Use dd command to write ISO to USB
        try await executeDDCommand(
            inputFile: isoPath,
            outputDevice: rawDevicePath,
            progressHandler: progressHandler
        )
        
        // Sync to ensure data is written
        try await syncDevice(rawDevicePath)
    }
    
    // MARK: - USB to ISO Operations
    
    func createISOFromUSB(usbDevice: USBManager.USBDevice, outputPath: String, progressHandler: @escaping (Double) -> Void) async throws {
        // Get the raw device identifier
        let rawDevicePath = try await getRawDevicePath(for: usbDevice)
        
        // Ensure output directory exists
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputDirectory = outputURL.deletingLastPathComponent()
        
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Use dd command to read from USB and create ISO
        try await executeDDCommand(
            inputDevice: rawDevicePath,
            outputFile: outputPath,
            progressHandler: progressHandler
        )
    }
    
    // MARK: - Helper Methods
    
    private func getRawDevicePath(for usbDevice: USBManager.USBDevice) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", usbDevice.devicePath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ISOManagerError.deviceInfoFailed
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ISOManagerError.deviceInfoParseFailed
        }
        
        // Parse the output to find the raw device path
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("Device Identifier:") {
                let components = line.components(separatedBy: ":")
                if components.count > 1 {
                    let deviceId = components[1].trimmingCharacters(in: .whitespaces)
                    return "/dev/r\(deviceId)"
                }
            }
        }
        
        throw ISOManagerError.rawDevicePathNotFound
    }
    
    private func executeDDCommand(inputFile: String? = nil, inputDevice: String? = nil, outputFile: String? = nil, outputDevice: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/dd")
        
        var arguments: [String] = []
        
        if let inputFile = inputFile {
            arguments.append("if=\(inputFile)")
        } else if let inputDevice = inputDevice {
            arguments.append("if=\(inputDevice)")
        }
        
        if let outputFile = outputFile {
            arguments.append("of=\(outputFile)")
        } else if let outputDevice = outputDevice {
            arguments.append("of=\(outputDevice)")
        }
        
        arguments.append("bs=1m")
        arguments.append("status=progress")
        
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        // Monitor progress
        let fileHandle = pipe.fileHandleForReading
        var progress: Double = 0.0
        
        while process.isRunning {
            let data = fileHandle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    // Parse dd progress output
                    if let parsedProgress = parseDDProgress(output) {
                        progress = parsedProgress
                        let currentProgress = progress
                        await MainActor.run {
                            progressHandler(currentProgress)
                        }
                    }
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ISOManagerError.ddCommandFailed
        }
        
        await MainActor.run {
            progressHandler(1.0)
        }
    }
    
    private func parseDDProgress(_ output: String) -> Double? {
        // Parse dd progress output like "1234567+0 records in"
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("records in") {
                let components = line.components(separatedBy: "+")
                if let recordsString = components.first,
                   let records = Int(recordsString.trimmingCharacters(in: .whitespaces)) {
                    // This is a simplified progress calculation
                    // In a real implementation, you'd want to track total size vs current size
                    return min(Double(records) / 10000.0, 1.0)
                }
            }
        }
        return nil
    }
    
    private func syncDevice(_ devicePath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sync")
        process.arguments = [devicePath]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ISOManagerError.syncFailed
        }
    }
    
    // MARK: - ISO Validation
    
    func validateISO(_ isoPath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: isoPath) else {
            return false
        }
        
        // Check if file has .iso extension
        let url = URL(fileURLWithPath: isoPath)
        guard url.pathExtension.lowercased() == "iso" else {
            return false
        }
        
        // Check file size (should be reasonable for an ISO)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: isoPath)
            if let fileSize = attributes[.size] as? NSNumber {
                let sizeInMB = fileSize.doubleValue / (1024 * 1024)
                return sizeInMB > 1 // At least 1MB
            }
        } catch {
            return false
        }
        
        return true
    }
    
    // MARK: - File Size Calculation
    
    func getFileSize(_ filePath: String) -> String? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            if let fileSize = attributes[.size] as? NSNumber {
                return ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file)
            }
        } catch {
            return nil
        }
        return nil
    }
}

// MARK: - Error Types

enum ISOManagerError: LocalizedError {
    case deviceUnmountFailed
    case isoFileNotFound
    case deviceInfoFailed
    case deviceInfoParseFailed
    case rawDevicePathNotFound
    case ddCommandFailed
    case syncFailed
    case invalidISOFile
    case insufficientSpace
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .deviceUnmountFailed:
            return "Failed to unmount USB device"
        case .isoFileNotFound:
            return "ISO file not found"
        case .deviceInfoFailed:
            return "Failed to get device information"
        case .deviceInfoParseFailed:
            return "Failed to parse device information"
        case .rawDevicePathNotFound:
            return "Could not find raw device path"
        case .ddCommandFailed:
            return "Failed to execute dd command"
        case .syncFailed:
            return "Failed to sync device"
        case .invalidISOFile:
            return "Invalid ISO file"
        case .insufficientSpace:
            return "Insufficient space on target device"
        case .permissionDenied:
            return "Permission denied. Please run with administrator privileges."
        }
    }
}
