# Bootable USB Utility

A macOS utility application for creating bootable USB drives from ISO files and creating ISO files from USB drives.

## Features

- **ISO to USB**: Create bootable USB drives from ISO image files
- **USB to ISO**: Create ISO image files from USB drives
- **Modern UI**: Clean, intuitive SwiftUI interface with drag-and-drop support
- **Progress Tracking**: Real-time progress updates during operations
- **Device Detection**: Automatic detection of connected USB devices
- **Safety Features**: Built-in validation and error handling

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for building from source)
- Administrator privileges (for USB operations)

## Installation

### Option 1: Build from Source

1. Clone or download this repository
2. Open `BootableUSBUtility.xcodeproj` in Xcode
3. Build and run the project (⌘+R)

### Option 2: Direct Build

```bash
cd /Users/dante/developer/BootableUSBUtility
xcodebuild -project BootableUSBUtility.xcodeproj -scheme BootableUSBUtility -configuration Release
```

## Usage

### Creating a Bootable USB from ISO

1. Launch the Bootable USB Utility
2. Select "ISO to USB" mode
3. Click "Browse" to select your ISO file
4. Choose a USB device from the list
5. Click "Create Bootable USB"
6. Wait for the process to complete

### Creating an ISO from USB

1. Launch the Bootable USB Utility
2. Select "USB to ISO" mode
3. Choose a USB device from the list
4. Click "Browse" to select output location for the ISO file
5. Click "Create ISO"
6. Wait for the process to complete

## Important Notes

⚠️ **Warning**: This utility will completely erase the target USB device. Make sure to backup any important data before proceeding.

⚠️ **Permissions**: The application requires administrator privileges to access USB devices. You may be prompted to enter your password.

## Technical Details

- Built with SwiftUI for modern macOS interface
- Uses `dd` command for low-level disk operations
- Implements proper device unmounting/mounting
- Includes progress monitoring and error handling
- Sandboxed with appropriate entitlements for security

## Troubleshooting

### Common Issues

1. **"Permission Denied" Error**
   - Run the application with administrator privileges
   - Check that the USB device is properly connected

2. **"Device Not Found" Error**
   - Ensure the USB device is properly mounted
   - Try refreshing the device list
   - Check that the device is not in use by other applications

3. **"ISO File Not Found" Error**
   - Verify the ISO file path is correct
   - Ensure the file has .iso extension
   - Check file permissions

### Debug Mode

To enable debug logging, set the environment variable:
```bash
export DEBUG=1
```

## Security

This application requires the following permissions:
- USB device access
- Disk arbitration access
- File system read/write access
- Temporary exception for /dev/ access

All operations are performed locally on your machine. No data is transmitted over the network.

## License

This project is provided as-is for educational and personal use. Please ensure you have the right to create copies of any ISO files you work with.

## Contributing

Feel free to submit issues and enhancement requests. This is a utility application designed for personal use and learning purposes.

## Disclaimer

Use this utility at your own risk. Always backup important data before performing disk operations. The authors are not responsible for any data loss or system damage.
