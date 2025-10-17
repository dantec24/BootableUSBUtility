import Foundation
import AppKit

class ISOManager: ObservableObject {
    
    // MARK: - ISO to USB Operations
    
    func burnISOToUSB(isoPath: String, usbDevice: USBManager.USBDevice, progressHandler: @escaping (Double) -> Void) async throws {
        print("🚀 Starting ISO to USB burn process")
        print("📁 ISO Path: \(isoPath)")
        print("💾 USB Device: \(usbDevice.name) (\(usbDevice.devicePath))")
        
        // Get the raw device identifier BEFORE unmounting (e.g., /dev/disk2)
        print("🔍 Getting raw device path...")
        let rawDevicePath = try await getRawDevicePath(for: usbDevice)
        print("✅ Raw device path: \(rawDevicePath)")
        
        // Check if we can access the raw device
        print("🔐 Checking raw device access permissions...")
        guard await checkRawDeviceAccess(rawDevicePath) else {
            print("❌ Cannot access raw device. This may require administrator privileges.")
            throw ISOManagerError.permissionDenied
        }
        print("✅ Raw device access confirmed")
        
        // First, unmount the USB device
        print("📤 Unmounting USB device...")
        let usbManager = USBManager()
        guard usbManager.unmountDevice(usbDevice) else {
            print("❌ Failed to unmount device")
            throw ISOManagerError.deviceUnmountFailed
        }
        print("✅ Device unmounted successfully")
        
        // Verify the ISO file exists
        print("🔍 Verifying ISO file exists...")
        guard FileManager.default.fileExists(atPath: isoPath) else {
            print("❌ ISO file not found: \(isoPath)")
            throw ISOManagerError.isoFileNotFound
        }
        print("✅ ISO file verified")
        
        // Use dd command to write ISO to USB
        print("💾 Starting dd command to write ISO to USB...")
        try await executeDDCommand(
            inputFile: isoPath,
            outputDevice: rawDevicePath,
            progressHandler: progressHandler
        )
        print("✅ dd command completed successfully")
        
        // Sync to ensure data is written
        print("🔄 Syncing device...")
        try await syncDevice(rawDevicePath)
        print("✅ Device synced successfully")
        print("🎉 ISO to USB burn process completed!")
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
    
    private func checkRawDeviceAccess(_ devicePath: String) async -> Bool {
        print("🔐 Testing access to raw device: \(devicePath)")
        
        // Try to open the device for reading to check permissions
        let fileHandle = FileHandle(forReadingAtPath: devicePath)
        if fileHandle != nil {
            fileHandle?.closeFile()
            print("✅ Raw device access confirmed")
            return true
        } else {
            print("❌ Cannot access raw device: \(devicePath)")
            return false
        }
    }
    
    private func getRawDevicePath(for usbDevice: USBManager.USBDevice) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", usbDevice.devicePath]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        guard let output = String(data: data, encoding: .utf8) else {
            throw ISOManagerError.deviceInfoParseFailed
        }
        
        // If diskutil failed, try to get device info by listing all disks
        if process.terminationStatus != 0 {
            print("diskutil info failed, trying list approach. Error: \(String(data: errorData, encoding: .utf8) ?? "Unknown error")")
            return try await getRawDevicePathByListing(deviceName: usbDevice.name)
        }
        
        // Parse the output to find the raw device path
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("Device Identifier:") {
                let components = line.components(separatedBy: ":")
                if components.count > 1 {
                    let deviceId = components[1].trimmingCharacters(in: .whitespaces)
                    print("🔍 Found device identifier: \(deviceId)")
                    // Ensure we're using the raw disk, not a partition
                    let rawDeviceId = deviceId.replacingOccurrences(of: "s[0-9]+$", with: "", options: .regularExpression)
                    print("🔍 Using raw device: /dev/r\(rawDeviceId)")
                    return "/dev/r\(rawDeviceId)"
                }
            }
        }
        
        throw ISOManagerError.rawDevicePathNotFound
    }
    
    private func getRawDevicePathByListing(deviceName: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["list"]
        
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
        
        // Parse the output to find the device by name
        let lines = output.components(separatedBy: .newlines)
        var currentDisk: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this line contains a disk identifier (starts with /dev/disk)
            if trimmedLine.hasPrefix("/dev/disk") && !trimmedLine.contains("s") {
                currentDisk = trimmedLine
            }
            
            // Check if this line contains our device name
            if let disk = currentDisk, trimmedLine.contains(deviceName) {
                print("🔍 Found device '\(deviceName)' on disk: \(disk)")
                // Return the raw disk (not partition) - remove 's' suffix if present
                let rawDisk = disk.replacingOccurrences(of: "/dev/", with: "").replacingOccurrences(of: "s[0-9]+$", with: "", options: .regularExpression)
                return "/dev/r\(rawDisk)"
            }
        }
        
        // If we found a disk but no specific device name match, use the last disk
        if let disk = currentDisk {
            print("🔍 Using last found disk: \(disk)")
            let rawDisk = disk.replacingOccurrences(of: "/dev/", with: "").replacingOccurrences(of: "s[0-9]+$", with: "", options: .regularExpression)
            return "/dev/r\(rawDisk)"
        }
        
        throw ISOManagerError.rawDevicePathNotFound
    }
    
    private func executeDDCommand(inputFile: String? = nil, inputDevice: String? = nil, outputFile: String? = nil, outputDevice: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        print("🔧 Setting up dd command...")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/dd")
        
        var arguments: [String] = []
        
        if let inputFile = inputFile {
            arguments.append("if=\(inputFile)")
            print("📥 Input file: \(inputFile)")
        } else if let inputDevice = inputDevice {
            arguments.append("if=\(inputDevice)")
            print("📥 Input device: \(inputDevice)")
        }
        
        if let outputFile = outputFile {
            arguments.append("of=\(outputFile)")
            print("📤 Output file: \(outputFile)")
        } else if let outputDevice = outputDevice {
            arguments.append("of=\(outputDevice)")
            print("📤 Output device: \(outputDevice)")
        }
        
        arguments.append("bs=1m")
        arguments.append("status=progress")
        
        process.arguments = arguments
        
        print("🔧 DD command arguments: \(arguments)")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        print("🚀 Starting dd process...")
        try process.run()
        print("✅ DD process started successfully")
        
        // Monitor progress
        print("📊 Starting progress monitoring...")
        let fileHandle = pipe.fileHandleForReading
        var progress: Double = 0.0
        var iterationCount = 0
        
        while process.isRunning {
            iterationCount += 1
            if iterationCount % 10 == 0 { // Log every 10 iterations (1 second)
                print("📊 Progress monitoring iteration \(iterationCount), process still running...")
            }
            
            let data = fileHandle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    print("📊 DD output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    // Parse dd progress output
                    if let parsedProgress = parseDDProgress(output) {
                        progress = parsedProgress
                        let currentProgress = progress
                        print("📊 Progress: \(Int(currentProgress * 100))%")
                        await MainActor.run {
                            progressHandler(currentProgress)
                        }
                    }
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        print("📊 Process finished, waiting for exit...")
        process.waitUntilExit()
        
        let exitCode = process.terminationStatus
        print("📊 Process exit code: \(exitCode)")
        
        // Read any remaining output
        let remainingData = fileHandle.readDataToEndOfFile()
        if !remainingData.isEmpty, let remainingOutput = String(data: remainingData, encoding: .utf8) {
            print("📊 Remaining output: \(remainingOutput)")
        }
        
        guard exitCode == 0 else {
            print("❌ DD command failed with exit code: \(exitCode)")
            
            // Check if it's a permission error
            if let remainingOutput = String(data: remainingData, encoding: .utf8),
               remainingOutput.contains("Permission denied") {
                print("🔐 Permission denied error detected. This requires administrator privileges.")
                throw ISOManagerError.permissionDenied
            } else {
                throw ISOManagerError.ddCommandFailed
            }
        }
        
        print("✅ DD command completed successfully")
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
