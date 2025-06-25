# Huginn macOS Agent

A comprehensive macOS system management agent with ODIN integration for remote administration, monitoring, and automation.

## Project Structure

This repository contains two main components:

### 1. Swift macOS Application (`Huggin-MACOS/`)
- **Native macOS app** built with SwiftUI
- **System monitoring** - Hardware, software, security status
- **Task execution** - Remote script and command execution
- **ODIN integration** - Secure agent communication with management platform
- **User interface** - Modern macOS-native dashboard and controls

### 2. TypeScript Integration Module (`src/`, `package.json`)
- **ODIN Agent Integration** - TypeScript/Node.js module for agent communication
- **Authentication** - JWT-based secure authentication with token management
- **Task execution engine** - Command, script, and software installation capabilities  
- **Telemetry collection** - Comprehensive system metrics and reporting
- **API bridge** - Interface between Swift app and ODIN management platform

## Key Features

### 🖥️ System Management
- Real-time hardware and software monitoring
- Security status tracking (firewall, encryption, updates)
- Application inventory and management
- System health diagnostics

### 🔐 Security & Authentication
- Secure JWT-based authentication
- macOS Keychain credential storage
- Automatic token refresh and re-enrollment
- Certificate-based device identification

### 🚀 Remote Administration
- Command and script execution
- Software installation (Homebrew, App Store, DMG, PKG)
- Policy application and compliance
- Task scheduling and automation

### 📊 Monitoring & Telemetry
- Hardware metrics (CPU, memory, storage, network)
- Software inventory and running processes
- Security posture and compliance status
- Performance monitoring and alerting

## Getting Started

### Prerequisites
- macOS 12.0+ (Monterey or later)
- Xcode 14.0+
- Node.js 16.0+

### Building the Swift Application
1. Open `Huggin-MACOS/Huggin-MACOS.xcodeproj` in Xcode
2. Build and run the project
3. Configure ODIN connection in the app settings

### Building the TypeScript Module
```bash
cd Huggin-MACOS
npm install
npm run build
```

### Running Tests
```bash
# TypeScript tests
npm test

# Swift tests (run from Xcode)
```

## Configuration

The agent requires configuration for ODIN platform integration:
- **Base URL** - ODIN management platform endpoint
- **Authentication** - Device enrollment and credentials
- **Polling intervals** - Task and telemetry collection frequency

## Documentation

- [`ODIN-INTEGRATION.md`](ODIN-INTEGRATION.md) - Original ODIN integration documentation
- [`ODIN-V3-INTEGRATION.md`](ODIN-V3-INTEGRATION.md) - V3 integration guide
- [`ODIN-V3-VERIFICATION.md`](ODIN-V3-VERIFICATION.md) - Integration verification steps
- [`Huggin-MACOS/README.md`](Huggin-MACOS/README.md) - TypeScript module documentation

## Architecture

```
┌─────────────────────────────────────────┐
│             macOS Application           │
│  ┌─────────────┐  ┌─────────────────────┤
│  │  SwiftUI    │  │   ODIN Services     │
│  │  Interface  │◄─┤  - Agent V3         │
│  │             │  │  - Network V3       │
│  │             │  │  - Token Manager    │
│  └─────────────┘  │  - Auth Manager     │
└────────────────────┴─────────────────────┘
           │
           ▼
┌─────────────────────────────────────────┐
│       TypeScript Integration           │
│  ┌─────────────┐  ┌─────────────────────┤
│  │   Agent     │  │   Services          │
│  │  Service    │◄─┤  - Task Executor    │
│  │             │  │  - Telemetry        │
│  │             │  │  - System Info      │
│  └─────────────┘  │  - Logger           │
└────────────────────┴─────────────────────┘
           │
           ▼
┌─────────────────────────────────────────┐
│          ODIN Platform                  │
│     (Supabase Backend)                  │
└─────────────────────────────────────────┘
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Support

For issues and support, please create an issue in this repository or contact the development team. 