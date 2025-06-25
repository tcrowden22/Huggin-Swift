# ODIN Agent V3 - Simplified Serial Number Authentication

## 🔄 Complete System Redesign

The ODIN integration has been completely redesigned based on the new simplified authentication system from your database team. **All JWT token complexity has been eliminated** in favor of a much simpler serial number-based approach.

## 🆕 New Components

### 1. **OdinSerialAuthManager.swift** (250 lines)
- **Serial number storage** using macOS Keychain for security
- **Device serial number detection** from system hardware
- **Simple enrollment state management** (enrolled/not enrolled)
- **No token lifecycle management** - once enrolled, agent is persistent
- **Automatic cleanup** if agent becomes invalid on server

### 2. **OdinNetworkServiceV3.swift** (400+ lines)
- **Direct API calls** to the new endpoints:
  - `/agent-enroll` - One-time enrollment with token
  - `/agent-checkin` - Regular status updates and task retrieval
  - `/agent-telemetry` - System telemetry transmission
- **No authentication headers** - serial number sent in request body
- **Supabase anon key** for basic API access
- **Comprehensive error handling** with automatic retry logic
- **404 detection** for agent-not-found scenarios

### 3. **OdinAgentServiceV3.swift** (700+ lines)
- **Main orchestration service** combining auth manager and network service
- **Background services**:
  - Check-in every 1 minute
  - Telemetry every 15 minutes
  - Health monitoring every 1 hour
- **Task management** with priority queuing
- **Real-time status tracking** and notifications
- **Automatic re-enrollment handling** when agent not found

### 4. **OdinSettingsViewV3.swift** (500+ lines)
- **Modern SwiftUI interface** optimized for macOS
- **Simple enrollment flow** - just enter token and click enroll
- **Real-time status monitoring** with connection health
- **Manual action buttons** for check-in and telemetry
- **Activity log** showing recent notifications
- **Agent reset functionality** for re-enrollment

## 🔑 Authentication Flow (Simplified)

### Step 1: One-Time Enrollment
1. **Admin generates enrollment token** in ODIN console
2. **User enters token** in Huginn app
3. **App gets device serial number** from system
4. **Enrollment API call** with token + device info
5. **Server validates and registers agent** using serial number
6. **App stores serial number** in keychain (no tokens!)

### Step 2: Persistent Operation
1. **All API calls** use stored serial number in request body
2. **No authentication headers** beyond Supabase anon key
3. **No token expiry** - agent remains valid until manually reset
4. **Automatic re-enrollment** if server returns 404 (agent not found)

## 📋 Configuration & Setup

### API Endpoints
- **Base URL**: `https://lfxfavntadlejwmkrvuv.supabase.co/functions/v1`
- **Supabase Anon Key**: Already configured in code
- **All endpoints use POST** with JSON request bodies

### Integration Steps

1. **Update ContentView.swift**:
```swift
// Replace old ODIN settings view
OdinSettingsViewV3()
```

2. **Add new files to Xcode project**:
- `OdinSerialAuthManager.swift`
- `OdinNetworkServiceV3.swift`
- `OdinAgentServiceV3.swift`
- `OdinSettingsViewV3.swift`

3. **Remove old ODIN files** (if desired):
- `OdinTokenManager.swift`
- `OdinNetworkService.swift`
- `OdinAgentServiceV2.swift`
- `OdinSettingsViewV2.swift`

## 🎯 Key Benefits

### ✅ **Massive Simplification**
- **No JWT tokens** - eliminates 90% of complexity
- **No refresh cycles** - no 30-day token rotations
- **No token storage** - just a simple serial number
- **No token validation** - server handles everything

### ✅ **Better Reliability**
- **Persistent connection** - once enrolled, stays enrolled
- **Automatic recovery** - handles agent-not-found gracefully
- **Simpler error handling** - fewer failure modes
- **No time-based failures** - no token expiry issues

### ✅ **Enhanced User Experience**
- **One-time setup** - enroll once, forget about it
- **No maintenance** - no monthly token renewals
- **Instant reconnection** - works immediately on app restart
- **Clear status** - enrolled or not enrolled, that's it

### ✅ **Production Ready**
- **App Store compatible** - no complex token storage
- **Security focused** - keychain storage for serial number
- **Error resilient** - comprehensive retry and fallback logic
- **Professional UI** - modern SwiftUI with real-time updates

## 🔄 Migration from V2

If you have the previous ODIN V2 system:

1. **Agents will need re-enrollment** - tokens are incompatible
2. **Old data will be ignored** - no migration needed
3. **Users should reset** old agents before upgrading
4. **New enrollment tokens** required from ODIN console

## 📊 API Request Examples

### Enrollment Request
```json
{
  "token": "shared_enrollment_token_from_admin",
  "deviceInfo": {
    "serial_number": "CV674J7M59",
    "hostname": "macbook-pro.local",
    "platform": "macOS",
    "agent_version": "3.0.0",
    "os": "macOS",
    "os_version": "15.5"
  }
}
```

### Check-in Request
```json
{
  "serial_number": "CV674J7M59",
  "system_info": {
    "uptime": 3600,
    "cpu_usage": 25,
    "memory_usage": 60,
    "disk_usage": 45
  }
}
```

### Telemetry Request
```json
{
  "serial_number": "CV674J7M59",
  "telemetry_data": {
    "hardware": {
      "cpu": "Apple Silicon",
      "memory": "16 GB",
      "disk": "SSD"
    },
    "software": {
      "os": "macOS",
      "version": "15.5",
      "agent_version": "3.0.0"
    },
    "security": {
      "firewall": "enabled",
      "gatekeeper": "enabled"
    }
  }
}
```

## 🚀 Ready for Integration

All components are complete and ready for integration. The system is:
- ✅ **Functionally complete** - all required features implemented
- ✅ **Error resilient** - comprehensive error handling
- ✅ **Production ready** - suitable for App Store distribution
- ✅ **User friendly** - simple enrollment and monitoring
- ✅ **Maintainable** - clean, documented Swift code

The new system eliminates the complexity of JWT token management while providing a more reliable and user-friendly experience for ODIN agent enrollment and operation. 