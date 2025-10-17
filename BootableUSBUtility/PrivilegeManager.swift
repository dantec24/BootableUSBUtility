import Foundation
import AppKit

class PrivilegeManager: ObservableObject {
    @Published var hasAdminPrivileges = false
    @Published var isCheckingPrivileges = true
    @Published var showPrivilegePrompt = false
    
    init() {
        checkAdminPrivileges()
    }
    
    func checkAdminPrivileges() {
        print("🔐 Checking admin privileges...")
        isCheckingPrivileges = true
        
        // Test if we can access raw disk devices
        let testDevice = "/dev/disk0" // Try to access the system disk
        let fileHandle = FileHandle(forReadingAtPath: testDevice)
        
        if fileHandle != nil {
            fileHandle?.closeFile()
            hasAdminPrivileges = true
            print("✅ Admin privileges confirmed")
        } else {
            hasAdminPrivileges = false
            print("❌ Admin privileges not available")
        }
        
        isCheckingPrivileges = false
        
        // Show prompt if no admin privileges
        if !hasAdminPrivileges {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showPrivilegePrompt = true
            }
        }
    }
    
    func requestAdminPrivileges() {
        print("🔐 Requesting admin privileges...")
        
        let alert = NSAlert()
        alert.messageText = "Administrator Privileges Required"
        alert.informativeText = "This app needs administrator privileges to write to USB devices. Would you like to restart the app with admin privileges?"
        alert.addButton(withTitle: "Restart with Admin")
        alert.addButton(withTitle: "Continue Without Admin")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Restart with admin privileges
            restartWithAdminPrivileges()
        case .alertSecondButtonReturn:
            // Continue without admin (may have limited functionality)
            hasAdminPrivileges = false
            showPrivilegePrompt = false
        case .alertThirdButtonReturn:
            // Cancel - exit app
            NSApplication.shared.terminate(nil)
        default:
            break
        }
    }
    
    private func restartWithAdminPrivileges() {
        print("🔄 Restarting app with admin privileges...")
        
        // Get the current app path
        let appPath = Bundle.main.bundlePath
        let appExecutable = Bundle.main.executablePath ?? "\(appPath)/Contents/MacOS/\(Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "BootableUSBUtility")"
        
        // Create the restart script
        let script = """
        #!/bin/bash
        echo "Restarting BootableUSBUtility with admin privileges..."
        sudo "\(appExecutable)"
        """
        
        // Write script to temporary file
        let tempScriptPath = "/tmp/restart_bootable_usb.sh"
        do {
            try script.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
            
            // Make script executable
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = ["+x", tempScriptPath]
            try process.run()
            process.waitUntilExit()
            
            // Execute the restart script
            let restartProcess = Process()
            restartProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            restartProcess.arguments = [tempScriptPath]
            try restartProcess.run()
            
            // Exit current app
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(nil)
            }
            
        } catch {
            print("❌ Failed to restart with admin privileges: \(error)")
            
            // Show fallback instructions
            showFallbackInstructions()
        }
    }
    
    private func showFallbackInstructions() {
        let alert = NSAlert()
        alert.messageText = "Manual Restart Required"
        alert.informativeText = """
        To run with admin privileges, please:
        
        1. Quit this app
        2. Open Terminal
        3. Run: sudo "\(Bundle.main.executablePath ?? "")"
        
        Or run from Terminal:
        sudo /Applications/BootableUSBUtility.app/Contents/MacOS/BootableUSBUtility
        """
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    func dismissPrivilegePrompt() {
        showPrivilegePrompt = false
    }
}
