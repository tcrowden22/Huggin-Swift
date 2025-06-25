#!/usr/bin/env node

import { agentService, logger, LogLevel } from '../index';
import * as http from 'http';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

interface BridgeConfig {
  port: number;
  odinUrl: string;
  logLevel: string;
}

class AgentBridge {
  private server?: http.Server;
  private config: BridgeConfig;
  private isRunning = false;

  constructor() {
    this.config = this.loadConfig();
    this.setupLogging();
  }

  private loadConfig(): BridgeConfig {
    const configPath = path.join(os.homedir(), '.huginn', 'agent-config.json');
    
    try {
      if (fs.existsSync(configPath)) {
        const configData = fs.readFileSync(configPath, 'utf8');
        return { ...this.getDefaultConfig(), ...JSON.parse(configData) };
      }
    } catch (error) {
      logger.warn('Failed to load config, using defaults', error);
    }
    
    return this.getDefaultConfig();
  }

  private getDefaultConfig(): BridgeConfig {
    return {
      port: 3001,
      odinUrl: process.env.ODIN_URL || 'https://lfxfavntadlejwmkrvuv.supabase.co/functions/v1',
      logLevel: process.env.LOG_LEVEL || 'INFO'
    };
  }

  private setupLogging(): void {
    const logLevel = LogLevel[this.config.logLevel as keyof typeof LogLevel] || LogLevel.INFO;
    logger.setLogLevel(logLevel);
    logger.enableFileLogging(true);
    logger.enableConsoleLogging(true);
  }

  async start(): Promise<void> {
    if (this.isRunning) return;

    logger.info('Starting Huginn Agent Bridge', { config: this.config });

    // Initialize the agent service
    const initialized = await agentService.initialize();
    if (!initialized) {
      throw new Error('Failed to initialize agent service');
    }

    await agentService.start();

    // Start HTTP server for Swift communication
    this.server = http.createServer((req, res) => {
      this.handleRequest(req, res);
    });

    this.server.listen(this.config.port, 'localhost', () => {
      logger.info(`Agent bridge listening on port ${this.config.port}`);
      this.isRunning = true;
    });

    // Setup agent event handlers
    this.setupEventHandlers();

    // Handle graceful shutdown
    process.on('SIGINT', () => this.shutdown());
    process.on('SIGTERM', () => this.shutdown());
  }

  private setupEventHandlers(): void {
    agentService.on('enrolled', (data) => {
      logger.info('Agent enrolled successfully', data);
      this.notifySwiftApp('agent_enrolled', data);
    });

    agentService.on('taskCompleted', (data) => {
      logger.info('Task completed', { taskId: data.task.task_id });
      this.notifySwiftApp('task_completed', {
        task_id: data.task.task_id,
        success: true,
        result: data.result
      });
    });

    agentService.on('taskFailed', (data) => {
      logger.error('Task failed', { taskId: data.task.task_id, error: data.result.error });
      this.notifySwiftApp('task_failed', {
        task_id: data.task.task_id,
        success: false,
        error: data.result.error
      });
    });

    agentService.on('telemetrySent', () => {
      logger.debug('Telemetry sent successfully');
      this.notifySwiftApp('telemetry_sent', { timestamp: new Date().toISOString() });
    });

    agentService.on('authenticationFailed', () => {
      logger.error('Authentication failed');
      this.notifySwiftApp('auth_failed', { timestamp: new Date().toISOString() });
    });
  }

  private async handleRequest(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.writeHead(200);
      res.end();
      return;
    }

    try {
      const url = new URL(req.url || '', `http://${req.headers.host}`);
      const path = url.pathname;

      switch (path) {
        case '/status':
          await this.handleStatus(req, res);
          break;
        case '/force-telemetry':
          await this.handleForceTelemetry(req, res);
          break;
        case '/force-token-refresh':
          await this.handleForceTokenRefresh(req, res);
          break;
        case '/logs':
          await this.handleGetLogs(req, res);
          break;
        case '/config':
          await this.handleConfig(req, res);
          break;
        default:
          res.writeHead(404);
          res.end(JSON.stringify({ error: 'Not found' }));
      }
    } catch (error) {
      logger.error('Request handling error', error);
      res.writeHead(500);
      res.end(JSON.stringify({ error: 'Internal server error' }));
    }
  }

  private async handleStatus(_req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    const status = agentService.getStatus();
    const health = {
      bridge_running: this.isRunning,
      agent_status: status,
      timestamp: new Date().toISOString()
    };

    res.writeHead(200);
    res.end(JSON.stringify(health));
  }

  private async handleForceTelemetry(_req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    try {
      await agentService.forceTelemetryReport();
      res.writeHead(200);
      res.end(JSON.stringify({ success: true, message: 'Telemetry sent' }));
    } catch (error) {
      res.writeHead(500);
      res.end(JSON.stringify({ success: false, error: error instanceof Error ? error.message : String(error) }));
    }
  }

  private async handleForceTokenRefresh(_req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    try {
      const refreshed = await agentService.forceTokenRefresh();
      res.writeHead(200);
      res.end(JSON.stringify({ success: refreshed, message: refreshed ? 'Token refreshed' : 'Token refresh failed' }));
    } catch (error) {
      res.writeHead(500);
      res.end(JSON.stringify({ success: false, error: error instanceof Error ? error.message : String(error) }));
    }
  }

  private async handleGetLogs(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    try {
      const url = new URL(req.url || '', `http://${req.headers.host}`);
      const count = parseInt(url.searchParams.get('count') || '100');
      
      const logs = logger.getRecentLogs(count);
      res.writeHead(200);
      res.end(JSON.stringify({ logs, count: logs.length }));
    } catch (error) {
      res.writeHead(500);
      res.end(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }));
    }
  }

  private async handleConfig(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    if (req.method === 'GET') {
      res.writeHead(200);
      res.end(JSON.stringify(this.config));
    } else if (req.method === 'POST') {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => {
        try {
          const newConfig = JSON.parse(body);
          this.updateConfig(newConfig);
          res.writeHead(200);
          res.end(JSON.stringify({ success: true, config: this.config }));
        } catch (error) {
          res.writeHead(400);
          res.end(JSON.stringify({ error: 'Invalid JSON' }));
        }
      });
    } else {
      res.writeHead(405);
      res.end(JSON.stringify({ error: 'Method not allowed' }));
    }
  }

  private updateConfig(newConfig: Partial<BridgeConfig>): void {
    this.config = { ...this.config, ...newConfig };
    
    const configPath = path.join(os.homedir(), '.huginn', 'agent-config.json');
    const configDir = path.dirname(configPath);
    
    if (!fs.existsSync(configDir)) {
      fs.mkdirSync(configDir, { recursive: true });
    }
    
    fs.writeFileSync(configPath, JSON.stringify(this.config, null, 2));
    logger.info('Configuration updated', this.config);
  }

  private notifySwiftApp(event: string, data: any): void {
    // Write to a file that the Swift app can monitor
    const notificationPath = path.join(os.homedir(), '.huginn', 'notifications.jsonl');
    const notification = {
      timestamp: new Date().toISOString(),
      event,
      data
    };
    
    try {
      fs.appendFileSync(notificationPath, JSON.stringify(notification) + '\n');
    } catch (error) {
      logger.error('Failed to write notification', error);
    }
  }

  async shutdown(): Promise<void> {
    logger.info('Shutting down agent bridge');
    
    if (this.server) {
      this.server.close();
    }
    
    await agentService.stop();
    this.isRunning = false;
    
    process.exit(0);
  }
}

// Start the bridge if this file is run directly
if (require.main === module) {
  const bridge = new AgentBridge();
  bridge.start().catch(error => {
    console.error('Failed to start agent bridge:', error);
    process.exit(1);
  });
}

export { AgentBridge }; 