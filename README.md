# Huginn ODIN Agent Integration Module

A comprehensive TypeScript-based integration module for connecting Huginn macOS agents with the ODIN management platform via Supabase. This module provides secure authentication, task execution, telemetry reporting, and system management capabilities.

## Features

### 🔐 Authentication & Token Management
- Secure JWT-based authentication with automatic token refresh
- Local keychain storage for credentials using macOS Keychain
- Automatic re-enrollment when tokens expire
- 5-minute buffer for token refresh to prevent expiration

### 🚀 Task Execution Engine
- **Command Execution**: Run shell commands with security safeguards
- **Script Execution**: Execute bash, Python, Node.js, and other scripts
- **Software Installation**: Support for Homebrew, Mac App Store, DMG, and PKG
- **Policy Application**: Security, configuration, and compliance policies
- Built-in safety mechanisms to prevent dangerous operations

### 📊 Comprehensive Telemetry
- **Hardware**: CPU, memory, storage, GPU, USB devices, network interfaces
- **Software**: OS info, installed applications, running services and processes
- **Security**: Firewall status, disk encryption, antivirus, updates
- **Network**: Interfaces, connections, usage statistics, WiFi info
- **Performance**: System load, uptime, alerts, resource utilization

### 🔄 Real-time Communication
- Automatic task polling (configurable interval)
- Exponential backoff retry logic for network failures
- 401 error handling with automatic token refresh
- Comprehensive error logging and debugging

### 📝 Advanced Logging
- Structured JSON logging with multiple levels (DEBUG, INFO, WARN, ERROR)
- Automatic log rotation (10MB max file size)
- Export functionality for support and debugging
- Console and file output with configurable levels

## Installation

```bash
npm install huginn-agent-integration
```

### Dependencies

The module requires the following dependencies:
- `keytar`: Secure credential storage
- `node-fetch`: HTTP client for API communication
- Node.js 16+ and macOS (darwin platform)

## Quick Start

```typescript
import { initializeAgent, shutdownAgent, getAgentHealth } from 'huginn-agent-integration';

// Initialize and start the agent
async function startAgent() {
  const initialized = await initializeAgent({
    baseUrl: 'https://your-supabase-url.supabase.co/functions/v1',
    pollInterval: 2 * 60 * 1000, // 2 minutes
    telemetryInterval: 30 * 60 * 1000, // 30 minutes
  });

  if (initialized) {
    console.log('Agent started successfully');
    
    // Check agent health
    const health = getAgentHealth();
    console.log('Agent status:', health.status);
  } else {
    console.error('Failed to initialize agent');
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  await shutdownAgent();
  process.exit(0);
});

startAgent();
```

## Advanced Usage

### Custom Configuration

```typescript
import { AgentService } from 'huginn-agent-integration';

const agent = new AgentService({
  baseUrl: 'https://your-supabase-url.supabase.co/functions/v1',
  serviceName: 'my-custom-agent',
  pollInterval: 60 * 1000, // 1 minute
  telemetryInterval: 15 * 60 * 1000, // 15 minutes
  maxRetries: 5
});

// Event handling
agent.on('enrolled', (data) => {
  console.log('Agent enrolled:', data.agent_id);
});

agent.on('taskCompleted', (data) => {
  console.log('Task completed:', data.task.task_id);
});

agent.on('taskFailed', (data) => {
  console.error('Task failed:', data.task.task_id, data.result.error);
});

agent.on('telemetrySent', (data) => {
  console.log('Telemetry sent successfully');
});

await agent.initialize();
await agent.start();
```

### Manual Task Execution

```typescript
import { taskExecutor } from 'huginn-agent-integration';

// Execute a command
const commandResult = await taskExecutor.execute({
  task_id: 'manual-command-1',
  type: 'run_command',
  payload: {
    command: 'brew',
    args: ['list', '--installed'],
    workingDirectory: '/usr/local'
  },
  priority: 1,
  created_at: new Date().toISOString()
});

// Execute a script
const scriptResult = await taskExecutor.execute({
  task_id: 'manual-script-1',
  type: 'run_script',
  payload: {
    content: `#!/bin/bash
echo "System Info:"
uname -a
df -h`,
    interpreter: 'bash'
  },
  priority: 1,
  created_at: new Date().toISOString()
});

// Install software
const installResult = await taskExecutor.execute({
  task_id: 'manual-install-1',
  type: 'install_software',
  payload: {
    name: 'git',
    source: 'homebrew',
    version: 'latest'
  },
  priority: 1,
  created_at: new Date().toISOString()
});
```

### System Information Collection

```typescript
import { systemInfoProvider, telemetryCollector } from 'huginn-agent-integration';

// Get basic device information
const deviceInfo = await systemInfoProvider.getDeviceInfo();
console.log('Device:', deviceInfo.hostname, deviceInfo.platform);

// Get comprehensive system metrics
const metrics = await systemInfoProvider.getSystemMetrics();
console.log('CPU Usage:', metrics.cpu.usage + '%');
console.log('Memory Usage:', metrics.memory.usage + '%');

// Get security information
const security = await systemInfoProvider.getSecurityInfo();
console.log('Firewall enabled:', security.firewall.enabled);
console.log('FileVault enabled:', security.encryption.enabled);

// Collect full telemetry
const telemetry = await telemetryCollector.collect();
console.log('Telemetry collected:', telemetry.timestamp);
```

### Custom Logging

```typescript
import { logger, LogLevel } from 'huginn-agent-integration';

// Configure logging
logger.setLogLevel(LogLevel.DEBUG);
logger.enableFileLogging(true);
logger.setLogFile('/var/log/huginn-agent.log');

// Structured logging
logger.info('Agent operation completed', {
  operation: 'software_install',
  package: 'git',
  duration: 1500
});

logger.logSecurityEvent('Firewall disabled', 'high', {
  user: 'admin',
  timestamp: new Date().toISOString()
});

// Export logs for support
const exported = logger.exportLogs('/tmp/huginn-logs.json');
if (exported) {
  console.log('Logs exported successfully');
}
```

## API Endpoints

The module communicates with the following ODIN Supabase edge functions:

### Authentication
- `POST /functions/v1/check-agent-status` - Agent enrollment and status check
- `POST /functions/v1/refresh-token` - Token refresh

### Task Management
- `POST /functions/v1/agent-get-tasks` - Fetch pending tasks
- `POST /functions/v1/agent-update-task` - Update task status and results

### Telemetry
- `POST /functions/v1/process-agent-telemetry` - Send system telemetry

## Task Types

### Command Execution (`run_command`)
```json
{
  "command": "brew",
  "args": ["install", "git"],
  "workingDirectory": "/usr/local",
  "environment": {"PATH": "/usr/local/bin:/usr/bin:/bin"},
  "timeout": 300000
}
```

### Script Execution (`run_script`)
```json
{
  "content": "#!/bin/bash\necho 'Hello World'",
  "interpreter": "bash",
  "arguments": ["arg1", "arg2"],
  "workingDirectory": "/tmp"
}
```

### Software Installation (`install_software`)
```json
{
  "name": "visual-studio-code",
  "source": "homebrew",
  "version": "latest",
  "installArgs": ["--cask"],
  "preInstallScript": "echo 'Preparing installation'",
  "postInstallScript": "echo 'Installation complete'"
}
```

### Policy Application (`apply_policy`)
```json
{
  "type": "security",
  "name": "firewall",
  "settings": {"enabled": true, "stealth_mode": true},
  "validation": "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate",
  "rollback": "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off"
}
```

## Security Features

### Command Safety
- Blacklist of dangerous commands (`rm -rf /`, `dd if=`, `shutdown`, etc.)
- Working directory restrictions
- Environment variable sanitization
- Timeout enforcement (default 5 minutes)

### Credential Security
- Encrypted storage in macOS Keychain
- Automatic token rotation
- Secure API communication with HTTPS
- No credentials stored in memory longer than necessary

### Execution Safety
- Temporary file cleanup
- Process isolation
- Resource limits (1MB output buffer)
- Script validation and sandboxing

## Development

### Building
```bash
npm run build
```

### Testing
```bash
npm test
npm run test:coverage
```

### Linting
```bash
npm run lint
npm run lint:fix
```

### Development Mode
```bash
npm run dev
```

## Configuration

### Environment Variables
- `NODE_ENV`: Set to 'production' for production logging
- `LOG_LEVEL`: Set log level (DEBUG, INFO, WARN, ERROR)

### Configuration Options
```typescript
interface AgentConfig {
  baseUrl: string;           // Supabase functions URL
  serviceName: string;       // Keychain service name
  pollInterval: number;      // Task polling interval (ms)
  telemetryInterval: number; // Telemetry reporting interval (ms)
  maxRetries: number;        // Maximum retry attempts
}
```

## Troubleshooting

### Common Issues

1. **Keychain Access Denied**
   - Ensure the application has keychain access permissions
   - Check macOS security settings

2. **Network Connectivity**
   - Verify Supabase URL is accessible
   - Check firewall and proxy settings

3. **Task Execution Failures**
   - Review logs for specific error messages
   - Ensure required tools (brew, mas) are installed
   - Check file permissions and paths

4. **High CPU/Memory Usage**
   - Adjust polling intervals
   - Review telemetry collection frequency
   - Check for resource-intensive tasks

### Debug Logging
```typescript
import { logger, LogLevel } from 'huginn-agent-integration';

logger.setLogLevel(LogLevel.DEBUG);
logger.enableConsoleLogging(true);
logger.enableFileLogging(true);
```

### Health Monitoring
```typescript
import { getAgentHealth } from 'huginn-agent-integration';

setInterval(() => {
  const health = getAgentHealth();
  if (health.status !== 'healthy') {
    console.error('Agent health issue:', health);
  }
}, 60000); // Check every minute
```

## License

MIT License - see LICENSE file for details.

## Support

For support and bug reports, please check the logs first:

```typescript
import { logger } from 'huginn-agent-integration';

// Export recent logs
logger.exportLogs('/tmp/huginn-debug-logs.json');
```

The exported logs contain comprehensive debugging information including API calls, task execution details, and system metrics. 