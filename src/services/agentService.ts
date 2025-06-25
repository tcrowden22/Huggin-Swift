import { EventEmitter } from 'events';
// import { app } from 'electron'; // Not needed for this implementation
import * as keytar from 'keytar';
import { exec } from 'child_process';
import { promisify } from 'util';
import { systemInfoProvider } from './systemInfoProvider';
import { telemetryCollector } from './telemetryCollector';
import { taskExecutor } from './taskExecutor';
import { logger } from '../utils/logger';

// const execAsync = promisify(exec); // Not used in current implementation

// Types
export interface AgentConfig {
  baseUrl: string;
  serviceName: string;
  pollInterval: number;
  telemetryInterval: number;
  maxRetries: number;
}

export interface AgentCredentials {
  access_token: string;
  refresh_token: string;
  agent_id: string;
  expires_at: number;
}

export interface DeviceInfo {
  hostname: string;
  platform: string;
  arch: string;
  version: string;
  cpuModel: string;
  totalMemory: number;
  macAddress: string;
  serialNumber?: string;
}

export interface Task {
  task_id: string;
  type: 'run_command' | 'run_script' | 'install_software' | 'apply_policy';
  payload: any;
  priority: number;
  timeout?: number;
  created_at: string;
}

export interface TaskResult {
  task_id: string;
  status: 'completed' | 'failed' | 'timeout';
  result?: any;
  error?: string;
  execution_time: number;
  completed_at: string;
}

export interface TelemetryData {
  hardware: any;
  software: any;
  security: any;
  network: any;
  policies: any;
  timestamp: string;
}

export class AgentService extends EventEmitter {
  private config: AgentConfig;
  private credentials: AgentCredentials | null = null;
  private isRunning = false;
  private taskPollTimer?: NodeJS.Timeout;
  private telemetryTimer?: NodeJS.Timeout;
  private refreshTimer?: NodeJS.Timeout;

  constructor(config: Partial<AgentConfig> = {}) {
    super();
    
    this.config = {
      baseUrl: 'https://lfxfavntadlejwmkrvuv.supabase.co/functions/v1',
      serviceName: 'huginn-agent',
      pollInterval: 2 * 60 * 1000, // 2 minutes
      telemetryInterval: 30 * 60 * 1000, // 30 minutes
      maxRetries: 3,
      ...config
    };

    logger.info('AgentService initialized', { config: this.config });
  }

  // ==================== Authentication & Token Management ====================

  async initialize(): Promise<boolean> {
    try {
      logger.info('Initializing agent service...');
      
      // Try to load existing credentials
      await this.loadCredentials();
      
      if (!this.credentials) {
        logger.info('No existing credentials found, starting enrollment process');
        return await this.enroll();
      }

      // Validate existing credentials
      if (this.isTokenExpired()) {
        logger.info('Token expired, attempting refresh');
        const refreshed = await this.refreshToken();
        if (!refreshed) {
          logger.warn('Token refresh failed, starting enrollment process');
          return await this.enroll();
        }
      }

      // Check agent status with ODIN
      const statusCheck = await this.checkAgentStatus();
      if (!statusCheck) {
        logger.warn('Agent status check failed, re-enrolling');
        return await this.enroll();
      }

      logger.info('Agent service initialized successfully');
      return true;
    } catch (error) {
      logger.error('Failed to initialize agent service', error);
      return false;
    }
  }

  private async enroll(): Promise<boolean> {
    try {
      const deviceInfo = await this.getDeviceInfo();
      
      logger.info('Starting enrollment process', { hostname: deviceInfo.hostname });
      
      const response = await this.makeRequest('/check-agent-status', {
        hostname: deviceInfo.hostname,
        deviceInfo
      }, false); // Don't use auth for enrollment

      if (response.exists && response.agent_id && response.api_token) {
        // Agent exists, store credentials
        this.credentials = {
          access_token: response.api_token,
          refresh_token: response.refresh_token || response.api_token,
          agent_id: response.agent_id,
          expires_at: Date.now() + (24 * 60 * 60 * 1000) // 24 hours default
        };

        await this.saveCredentials();
        this.scheduleTokenRefresh();
        
        logger.info('Enrollment successful', { agent_id: response.agent_id });
        this.emit('enrolled', { agent_id: response.agent_id });
        return true;
      } else {
        logger.error('Enrollment failed: Invalid response from server', response);
        this.emit('enrollmentFailed', { reason: 'Invalid server response' });
        return false;
      }
    } catch (error) {
      logger.error('Enrollment failed', error);
      this.emit('enrollmentFailed', { error });
      return false;
    }
  }

  private async loadCredentials(): Promise<void> {
    try {
      const stored = await keytar.getPassword(this.config.serviceName, 'credentials');
      if (stored) {
        this.credentials = JSON.parse(stored);
        logger.debug('Credentials loaded from keychain');
      }
    } catch (error) {
      logger.error('Failed to load credentials', error);
    }
  }

  private async saveCredentials(): Promise<void> {
    if (!this.credentials) return;
    
    try {
      await keytar.setPassword(
        this.config.serviceName, 
        'credentials', 
        JSON.stringify(this.credentials)
      );
      logger.debug('Credentials saved to keychain');
    } catch (error) {
      logger.error('Failed to save credentials', error);
    }
  }

  private async clearCredentials(): Promise<void> {
    try {
      await keytar.deletePassword(this.config.serviceName, 'credentials');
      this.credentials = null;
      logger.info('Credentials cleared');
    } catch (error) {
      logger.error('Failed to clear credentials', error);
    }
  }

  private isTokenExpired(): boolean {
    if (!this.credentials) return true;
    
    // Refresh 5 minutes before expiration
    const refreshBuffer = 5 * 60 * 1000;
    return Date.now() >= (this.credentials.expires_at - refreshBuffer);
  }

  private async refreshToken(): Promise<boolean> {
    if (!this.credentials?.refresh_token) return false;

    try {
      logger.info('Refreshing access token');
      
      const response = await this.makeRequest('/refresh-token', {
        refresh_token: this.credentials.refresh_token,
        agent_id: this.credentials.agent_id
      }, false);

      if (response.access_token) {
        this.credentials.access_token = response.access_token;
        this.credentials.expires_at = response.expires_at || (Date.now() + (24 * 60 * 60 * 1000));
        
        if (response.refresh_token) {
          this.credentials.refresh_token = response.refresh_token;
        }

        await this.saveCredentials();
        this.scheduleTokenRefresh();
        
        logger.info('Token refreshed successfully');
        this.emit('tokenRefreshed');
        return true;
      }
      
      return false;
    } catch (error) {
      logger.error('Token refresh failed', error);
      this.emit('tokenRefreshFailed', { error });
      return false;
    }
  }

  private scheduleTokenRefresh(): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
    }

    if (!this.credentials) return;

    const refreshTime = this.credentials.expires_at - Date.now() - (5 * 60 * 1000); // 5 minutes before expiry
    
    if (refreshTime > 0) {
      this.refreshTimer = setTimeout(() => {
        this.refreshToken();
      }, refreshTime);
      
      logger.debug('Token refresh scheduled', { refreshIn: refreshTime });
    }
  }

  // ==================== API Communication ====================

  private async makeRequest(
    endpoint: string, 
    data: any, 
    useAuth: boolean = true,
    retryCount: number = 0
  ): Promise<any> {
    const url = `${this.config.baseUrl}${endpoint}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    if (useAuth && this.credentials?.access_token) {
      headers['Authorization'] = `Bearer ${this.credentials.access_token}`;
    }

    try {
      logger.debug('Making API request', { url, useAuth, retryCount });
      
      const response = await fetch(url, {
        method: 'POST',
        headers,
        body: JSON.stringify(data)
      });

      if (response.status === 401 && useAuth) {
        logger.warn('Received 401, attempting token refresh');
        const refreshed = await this.refreshToken();
        
        if (refreshed && retryCount < this.config.maxRetries) {
          return this.makeRequest(endpoint, data, useAuth, retryCount + 1);
        } else {
          await this.clearCredentials();
          this.emit('authenticationFailed');
          throw new Error('Authentication failed and token refresh unsuccessful');
        }
      }

      if (response.status === 404) {
        logger.warn('API endpoint not found', { url });
        return null;
      }

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const result = await response.json();
      logger.debug('API request successful', { url, status: response.status });
      return result;

    } catch (error) {
      logger.error('API request failed', { url, error, retryCount });
      
      if (retryCount < this.config.maxRetries) {
        const backoffDelay = Math.pow(2, retryCount) * 1000; // Exponential backoff
        logger.info(`Retrying request in ${backoffDelay}ms`, { url, retryCount });
        
        await new Promise(resolve => setTimeout(resolve, backoffDelay));
        return this.makeRequest(endpoint, data, useAuth, retryCount + 1);
      }
      
      throw error;
    }
  }

  private async checkAgentStatus(): Promise<boolean> {
    try {
      const deviceInfo = await this.getDeviceInfo();
      const response = await this.makeRequest('/check-agent-status', {
        hostname: deviceInfo.hostname,
        deviceInfo,
        agent_id: this.credentials?.agent_id
      });

      return response && response.exists;
    } catch (error) {
      logger.error('Agent status check failed', error);
      return false;
    }
  }

  // ==================== Task Management ====================

  async start(): Promise<void> {
    if (this.isRunning) return;

    logger.info('Starting agent service');
    this.isRunning = true;

    // Start task polling
    this.startTaskPolling();
    
    // Start telemetry reporting
    this.startTelemetryReporting();
    
    this.emit('started');
  }

  async stop(): Promise<void> {
    if (!this.isRunning) return;

    logger.info('Stopping agent service');
    this.isRunning = false;

    if (this.taskPollTimer) {
      clearInterval(this.taskPollTimer);
      this.taskPollTimer = undefined as any;
    }

    if (this.telemetryTimer) {
      clearInterval(this.telemetryTimer);
      this.telemetryTimer = undefined as any;
    }

    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = undefined as any;
    }

    this.emit('stopped');
  }

  private startTaskPolling(): void {
    this.taskPollTimer = setInterval(async () => {
      try {
        await this.fetchAndExecuteTasks();
      } catch (error) {
        logger.error('Task polling error', error);
      }
    }, this.config.pollInterval);

    // Execute immediately
    this.fetchAndExecuteTasks();
  }

  private async fetchAndExecuteTasks(): Promise<void> {
    try {
      logger.debug('Fetching tasks from ODIN');
      
      const response = await this.makeRequest('/agent-get-tasks', {
        agent_id: this.credentials?.agent_id
      });

      if (response?.tasks && Array.isArray(response.tasks)) {
        logger.info(`Received ${response.tasks.length} tasks`);
        
        for (const task of response.tasks) {
          this.executeTask(task);
        }
      }
    } catch (error) {
      logger.error('Failed to fetch tasks', error);
    }
  }

  private async executeTask(task: Task): Promise<void> {
    logger.info('Executing task', { task_id: task.task_id, type: task.type });
    
    const startTime = Date.now();
    let result: TaskResult;

    try {
      // Update task status to running
      await this.updateTaskStatus(task.task_id, 'running');

      // Execute the task based on type
      const executionResult = await taskExecutor.execute(task);
      
      result = {
        task_id: task.task_id,
        status: 'completed',
        result: executionResult,
        execution_time: Date.now() - startTime,
        completed_at: new Date().toISOString()
      };

      logger.info('Task completed successfully', { task_id: task.task_id });
      this.emit('taskCompleted', { task, result });

    } catch (error) {
      result = {
        task_id: task.task_id,
        status: 'failed',
        error: error instanceof Error ? error.message : String(error),
        execution_time: Date.now() - startTime,
        completed_at: new Date().toISOString()
      };

      logger.error('Task execution failed', { task_id: task.task_id, error });
      this.emit('taskFailed', { task, result });
    }

    // Report task completion
    await this.updateTaskStatus(task.task_id, result.status, result);
  }

  private async updateTaskStatus(
    taskId: string, 
    status: string, 
    result?: Partial<TaskResult>
  ): Promise<void> {
    try {
      await this.makeRequest('/agent-update-task', {
        agent_id: this.credentials?.agent_id,
        task_id: taskId,
        status,
        ...result
      });

      logger.debug('Task status updated', { taskId, status });
    } catch (error) {
      logger.error('Failed to update task status', { taskId, status, error });
    }
  }

  // ==================== Telemetry Reporting ====================

  private startTelemetryReporting(): void {
    this.telemetryTimer = setInterval(async () => {
      try {
        await this.sendTelemetry();
      } catch (error) {
        logger.error('Telemetry reporting error', error);
      }
    }, this.config.telemetryInterval);

    // Send immediately
    this.sendTelemetry();
  }

  private async sendTelemetry(): Promise<void> {
    try {
      logger.debug('Collecting and sending telemetry');
      
      const telemetryData = await telemetryCollector.collect();
      
      await this.makeRequest('/process-agent-telemetry', {
        agent_id: this.credentials?.agent_id,
        telemetry: telemetryData,
        timestamp: new Date().toISOString()
      });

      logger.debug('Telemetry sent successfully');
      this.emit('telemetrySent', { data: telemetryData });

    } catch (error) {
      logger.error('Failed to send telemetry', error);
      this.emit('telemetryFailed', { error });
    }
  }

  // ==================== Utility Methods ====================

  private async getDeviceInfo(): Promise<DeviceInfo> {
    return await systemInfoProvider.getDeviceInfo();
  }

  // Public methods for external use
  async forceTokenRefresh(): Promise<boolean> {
    logger.info('Forcing token refresh');
    return await this.refreshToken();
  }

  async forceTelemetryReport(): Promise<void> {
    logger.info('Forcing telemetry report');
    await this.sendTelemetry();
  }

  getAgentId(): string | null {
    return this.credentials?.agent_id || null;
  }

  isAuthenticated(): boolean {
    return !!(this.credentials?.access_token && !this.isTokenExpired());
  }

  getStatus(): {
    running: boolean;
    authenticated: boolean;
    agentId: string | null;
    tokenExpiry: number | null;
  } {
    return {
      running: this.isRunning,
      authenticated: this.isAuthenticated(),
      agentId: this.getAgentId(),
      tokenExpiry: this.credentials?.expires_at || null
    };
  }
}

// Export singleton instance
export const agentService = new AgentService(); 