// Main Agent Integration Module
export { AgentService, agentService } from './services/agentService';
export { systemInfoProvider } from './services/systemInfoProvider';
export { telemetryCollector } from './services/telemetryCollector';
export { taskExecutor } from './services/taskExecutor';
export { logger, LogLevel } from './utils/logger';

// Types
export type {
  AgentConfig,
  AgentCredentials,
  DeviceInfo,
  Task,
  TaskResult,
  TelemetryData
} from './services/agentService';

export type {
  // SystemMetrics, // Not exported from telemetryCollector
  HardwareTelemetry,
  SoftwareTelemetry,
  SecurityTelemetry,
  NetworkTelemetry,
  PolicyTelemetry,
  PerformanceTelemetry
} from './services/telemetryCollector';

export type {
  TaskExecutionResult,
  CommandPayload,
  ScriptPayload,
  SoftwarePayload,
  PolicyPayload
} from './services/taskExecutor';

export type { LogEntry } from './utils/logger';

// Main initialization function
export async function initializeAgent(config?: Partial<import('./services/agentService').AgentConfig>): Promise<boolean> {
  const { agentService } = await import('./services/agentService');
  
  if (config) {
    // Create new instance with custom config
    const { AgentService } = await import('./services/agentService');
    const customAgent = new AgentService(config);
    const initialized = await customAgent.initialize();
    if (initialized) {
      await customAgent.start();
    }
    return initialized;
  } else {
    // Use singleton instance
    const initialized = await agentService.initialize();
    if (initialized) {
      await agentService.start();
    }
    return initialized;
  }
}

// Graceful shutdown function
export async function shutdownAgent(): Promise<void> {
  const { agentService } = await import('./services/agentService');
  await agentService.stop();
}

// Health check function
export function getAgentHealth(): {
  status: 'healthy' | 'degraded' | 'unhealthy';
  details: any;
} {
  const { agentService } = require('./services/agentService');
  const status = agentService.getStatus();
  
  let healthStatus: 'healthy' | 'degraded' | 'unhealthy' = 'unhealthy';
  
  if (status.running && status.authenticated) {
    healthStatus = 'healthy';
  } else if (status.running || status.authenticated) {
    healthStatus = 'degraded';
  }
  
  return {
    status: healthStatus,
    details: {
      ...status,
      timestamp: new Date().toISOString()
    }
  };
}

// Export version
export const VERSION = '1.0.0'; 