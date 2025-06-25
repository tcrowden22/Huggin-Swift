import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3
}

export interface LogEntry {
  timestamp: string;
  level: string;
  message: string;
  context?: any;
  error?: any;
}

class Logger {
  private logLevel: LogLevel = LogLevel.INFO;
  private logFile?: string;
  private enableConsole: boolean = true;
  private enableFile: boolean = false;

  constructor() {
    // Set up default log file in user's home directory
    const logDir = path.join(os.homedir(), '.huginn', 'logs');
    this.ensureLogDirectory(logDir);
    this.logFile = path.join(logDir, 'agent.log');
    
    // Enable file logging by default in production
    this.enableFile = process.env.NODE_ENV === 'production';
    
    // Set log level from environment
    const envLogLevel = process.env.LOG_LEVEL?.toUpperCase();
    if (envLogLevel && envLogLevel in LogLevel) {
      this.logLevel = LogLevel[envLogLevel as keyof typeof LogLevel];
    }
  }

  setLogLevel(level: LogLevel): void {
    this.logLevel = level;
  }

  setLogFile(filePath: string): void {
    this.logFile = filePath;
    this.enableFile = true;
  }

  enableConsoleLogging(enabled: boolean): void {
    this.enableConsole = enabled;
  }

  enableFileLogging(enabled: boolean): void {
    this.enableFile = enabled;
  }

  debug(message: string, context?: any): void {
    this.log(LogLevel.DEBUG, message, context);
  }

  info(message: string, context?: any): void {
    this.log(LogLevel.INFO, message, context);
  }

  warn(message: string, context?: any): void {
    this.log(LogLevel.WARN, message, context);
  }

  error(message: string, error?: any, context?: any): void {
    this.log(LogLevel.ERROR, message, context, error);
  }

  private log(level: LogLevel, message: string, context?: any, error?: any): void {
    if (level < this.logLevel) {
      return;
    }

    const timestamp = new Date().toISOString();
    const levelName = LogLevel[level];
    
    const logEntry: LogEntry = {
      timestamp,
      level: levelName,
      message,
      context,
      error: error ? this.serializeError(error) : undefined
    };

    if (this.enableConsole) {
      this.logToConsole(logEntry);
    }

    if (this.enableFile && this.logFile) {
      this.logToFile(logEntry);
    }
  }

  private logToConsole(entry: LogEntry): void {
    const { timestamp, level, message, context, error } = entry;
    const timeStr = new Date(timestamp).toLocaleTimeString();
    
    let logMessage = `[${timeStr}] ${level}: ${message}`;
    
    if (context) {
      logMessage += ` ${JSON.stringify(context)}`;
    }
    
    if (error) {
      logMessage += ` ERROR: ${JSON.stringify(error)}`;
    }

    switch (entry.level) {
      case 'DEBUG':
        console.debug(logMessage);
        break;
      case 'INFO':
        console.info(logMessage);
        break;
      case 'WARN':
        console.warn(logMessage);
        break;
      case 'ERROR':
        console.error(logMessage);
        break;
    }
  }

  private logToFile(entry: LogEntry): void {
    if (!this.logFile) return;

    try {
      const logLine = JSON.stringify(entry) + '\n';
      fs.appendFileSync(this.logFile, logLine, 'utf8');
    } catch (error) {
      console.error('Failed to write to log file:', error);
    }
  }

  private serializeError(error: any): any {
    if (error instanceof Error) {
      return {
        name: error.name,
        message: error.message,
        stack: error.stack
      };
    }
    return error;
  }

  private ensureLogDirectory(dir: string): void {
    try {
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    } catch (error) {
      console.warn('Failed to create log directory:', error);
    }
  }

  // Utility methods for structured logging
  logApiRequest(method: string, url: string, statusCode?: number, duration?: number): void {
    this.info('API Request', {
      method,
      url,
      statusCode,
      duration
    });
  }

  logTaskExecution(taskId: string, type: string, success: boolean, duration: number): void {
    const level = success ? LogLevel.INFO : LogLevel.ERROR;
    this.log(level, 'Task Execution', {
      taskId,
      type,
      success,
      duration
    });
  }

  logSystemMetric(metric: string, value: number, unit?: string): void {
    this.debug('System Metric', {
      metric,
      value,
      unit
    });
  }

  logSecurityEvent(event: string, severity: 'low' | 'medium' | 'high' | 'critical', details?: any): void {
    const level = severity === 'critical' || severity === 'high' ? LogLevel.ERROR : LogLevel.WARN;
    this.log(level, `Security Event: ${event}`, {
      severity,
      details
    });
  }

  // Log rotation
  rotateLogFile(): void {
    if (!this.logFile || !fs.existsSync(this.logFile)) {
      return;
    }

    try {
      const stats = fs.statSync(this.logFile);
      const maxSize = 10 * 1024 * 1024; // 10MB
      
      if (stats.size > maxSize) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const rotatedFile = `${this.logFile}.${timestamp}`;
        
        fs.renameSync(this.logFile, rotatedFile);
        this.info('Log file rotated', { oldFile: rotatedFile, newFile: this.logFile });
        
        // Keep only last 5 rotated files
        this.cleanupOldLogFiles();
      }
    } catch (error) {
      console.error('Failed to rotate log file:', error);
    }
  }

  private cleanupOldLogFiles(): void {
    if (!this.logFile) return;

    try {
      const logDir = path.dirname(this.logFile);
      const logFileName = path.basename(this.logFile);
      
      const files = fs.readdirSync(logDir)
        .filter(file => file.startsWith(logFileName) && file !== logFileName)
        .map(file => ({
          name: file,
          path: path.join(logDir, file),
          stats: fs.statSync(path.join(logDir, file))
        }))
        .sort((a, b) => b.stats.mtime.getTime() - a.stats.mtime.getTime());

      // Keep only the 5 most recent files
      const filesToDelete = files.slice(5);
      
      for (const file of filesToDelete) {
        fs.unlinkSync(file.path);
        this.debug('Deleted old log file', { file: file.name });
      }
    } catch (error) {
      console.error('Failed to cleanup old log files:', error);
    }
  }

  // Get recent log entries for debugging
  getRecentLogs(count: number = 100): LogEntry[] {
    if (!this.logFile || !fs.existsSync(this.logFile)) {
      return [];
    }

    try {
      const content = fs.readFileSync(this.logFile, 'utf8');
      const lines = content.trim().split('\n');
      const recentLines = lines.slice(-count);
      
      return recentLines
        .map(line => {
          try {
            return JSON.parse(line) as LogEntry;
          } catch {
            return null;
          }
        })
        .filter(entry => entry !== null) as LogEntry[];
    } catch (error) {
      console.error('Failed to read log file:', error);
      return [];
    }
  }

  // Export logs for support
  exportLogs(outputPath: string, fromDate?: Date, toDate?: Date): boolean {
    try {
      const logs = this.getRecentLogs(10000); // Get more logs for export
      
      let filteredLogs = logs;
      if (fromDate || toDate) {
        filteredLogs = logs.filter(log => {
          const logDate = new Date(log.timestamp);
          if (fromDate && logDate < fromDate) return false;
          if (toDate && logDate > toDate) return false;
          return true;
        });
      }

      const exportData = {
        exportedAt: new Date().toISOString(),
        agentVersion: '1.0.0',
        platform: os.platform(),
        hostname: os.hostname(),
        totalLogs: filteredLogs.length,
        logs: filteredLogs
      };

      fs.writeFileSync(outputPath, JSON.stringify(exportData, null, 2), 'utf8');
      this.info('Logs exported successfully', { outputPath, count: filteredLogs.length });
      return true;
    } catch (error) {
      this.error('Failed to export logs', error, { outputPath });
      return false;
    }
  }
}

// Export singleton instance
export const logger = new Logger();

// Auto-rotate logs every hour
setInterval(() => {
  logger.rotateLogFile();
}, 60 * 60 * 1000); // 1 hour 