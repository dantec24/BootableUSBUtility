import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var usbManager = USBManager()
    @StateObject private var isoManager = ISOManager()
    @StateObject private var privilegeManager = PrivilegeManager()
    @State private var selectedISOPath: String = ""
    @State private var selectedUSBDevice: USBManager.USBDevice?
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var statusMessage = "Ready"
    @State private var showingFilePicker = false
    @State private var operationMode: OperationMode = .isoToUSB
    
    enum OperationMode: String, CaseIterable {
        case isoToUSB = "ISO to USB"
        case usbToISO = "USB to ISO"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Bootable USB Utility")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Create bootable USB drives from ISO files and vice versa")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Privilege Status Indicator
                HStack {
                    Image(systemName: privilegeManager.hasAdminPrivileges ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundColor(privilegeManager.hasAdminPrivileges ? .green : .orange)
                    
                    Text(privilegeManager.hasAdminPrivileges ? "Admin privileges available" : "Admin privileges required")
                        .font(.caption)
                        .foregroundColor(privilegeManager.hasAdminPrivileges ? .green : .orange)
                }
                .padding(.top, 4)
            }
            .padding(.top, 20)
            
            // Operation Mode Selector
            Picker("Operation Mode", selection: $operationMode) {
                ForEach(OperationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            VStack(spacing: 16) {
                if operationMode == .isoToUSB {
                    // ISO to USB Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select ISO File")
                            .font(.headline)
                        
                        HStack {
                            TextField("No ISO file selected", text: $selectedISOPath)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(true)
                            
                            Button("Browse") {
                                showingFilePicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("USB Device")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        if usbManager.availableDevices.isEmpty {
                            Text("No USB devices detected")
                                .foregroundColor(.secondary)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(usbManager.availableDevices, id: \.identifier) { device in
                                        USBDeviceRow(
                                            device: device,
                                            isSelected: selectedUSBDevice?.identifier == device.identifier
                                        ) {
                                            selectedUSBDevice = device
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                } else {
                    // USB to ISO Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select USB Device")
                            .font(.headline)
                        
                        if usbManager.availableDevices.isEmpty {
                            Text("No USB devices detected")
                                .foregroundColor(.secondary)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(usbManager.availableDevices, id: \.identifier) { device in
                                        USBDeviceRow(
                                            device: device,
                                            isSelected: selectedUSBDevice?.identifier == device.identifier
                                        ) {
                                            selectedUSBDevice = device
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                        
                        Text("ISO Output Location")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        HStack {
                            TextField("Choose output location", text: $selectedISOPath)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(true)
                            
                            Button("Browse") {
                                showingFilePicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Progress Section
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Action Buttons
            HStack(spacing: 16) {
                Button("Refresh Devices") {
                    usbManager.refreshDevices()
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
                
                Button(action: {
                    if !privilegeManager.hasAdminPrivileges {
                        privilegeManager.requestAdminPrivileges()
                        return
                    }
                    
                    if operationMode == .isoToUSB {
                        startISOBurn()
                    } else {
                        startISOCreation()
                    }
                }) {
                    HStack {
                        if !privilegeManager.hasAdminPrivileges {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        Text(operationMode == .isoToUSB ? "Create Bootable USB" : "Create ISO")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartOperation)
                .foregroundColor(!privilegeManager.hasAdminPrivileges ? .orange : .primary)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .frame(minWidth: 600, minHeight: 500)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: operationMode == .isoToUSB ? [UTType(filenameExtension: "iso")!] : [UTType.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedISOPath = url.path
                }
            case .failure(let error):
                statusMessage = "File selection failed: \(error.localizedDescription)"
            }
        }
        .onAppear {
            usbManager.refreshDevices()
        }
        .alert("Administrator Privileges Required", isPresented: $privilegeManager.showPrivilegePrompt) {
            Button("Restart with Admin") {
                privilegeManager.requestAdminPrivileges()
            }
            Button("Continue Without Admin") {
                privilegeManager.dismissPrivilegePrompt()
            }
            Button("Cancel") {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text("This app needs administrator privileges to write to USB devices. Would you like to restart the app with admin privileges?")
        }
    }
    
    private var canStartOperation: Bool {
        if operationMode == .isoToUSB {
            return !selectedISOPath.isEmpty && selectedUSBDevice != nil && !isProcessing
        } else {
            return selectedUSBDevice != nil && !selectedISOPath.isEmpty && !isProcessing
        }
    }
    
    private func startISOBurn() {
        guard let device = selectedUSBDevice else { return }
        
        isProcessing = true
        progress = 0.0
        statusMessage = "Starting ISO burn process..."
        
        Task {
            do {
                print("🎯 ContentView: Starting burn task")
                try await isoManager.burnISOToUSB(
                    isoPath: selectedISOPath,
                    usbDevice: device,
                    progressHandler: { progress in
                        DispatchQueue.main.async {
                            self.progress = progress
                            self.statusMessage = "Burning ISO... \(Int(progress * 100))%"
                        }
                    }
                )
                
                print("🎯 ContentView: Burn completed successfully")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "ISO successfully burned to USB!"
                    self.progress = 1.0
                    // Refresh device list after successful operation
                    self.usbManager.refreshDevices()
                }
            } catch {
                print("🎯 ContentView: Error occurred: \(error)")
                print("🎯 ContentView: Error type: \(type(of: error))")
                print("🎯 ContentView: Error description: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func startISOCreation() {
        guard let device = selectedUSBDevice else { return }
        
        isProcessing = true
        progress = 0.0
        statusMessage = "Starting ISO creation process..."
        
        Task {
            do {
                try await isoManager.createISOFromUSB(
                    usbDevice: device,
                    outputPath: selectedISOPath,
                    progressHandler: { progress in
                        DispatchQueue.main.async {
                            self.progress = progress
                            self.statusMessage = "Creating ISO... \(Int(progress * 100))%"
                        }
                    }
                )
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "ISO successfully created from USB!"
                    self.progress = 1.0
                    // Refresh device list after successful operation
                    self.usbManager.refreshDevices()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct USBDeviceRow: View {
    let device: USBManager.USBDevice
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "externaldrive")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(device.size) • \(device.identifier)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ContentView()
}
