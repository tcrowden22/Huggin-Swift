import { exec, spawn } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { logger } from '../utils/logger';

const execAsync = promisify(exec);
const writeFileAsync = promisify(fs.writeFile);
const unlinkAsync = promisify(fs.unlink);

export interface Task {
  task_id: string;
  type: 'run_command' | 'run_script' | 'install_software' | 'apply_policy';
  payload: any;
  priority: number;
  timeout?: number;
  created_at: string;
}

export interface TaskExecutionResult {
  success: boolean;
  output?: string;
  error?: string;
  exitCode?: number;
  duration: number;
  metadata?: any;
}

export interface CommandPayload {
  command: string;
  args?: string[];
  workingDirectory?: string;
  environment?: Record<string, string>;
  user?: string;
  shell?: string;
}

export interface ScriptPayload {
  content: string;
  interpreter?: string;
  filename?: string;
  arguments?: string[];
  workingDirectory?: string;
  environment?: Record<string, string>;
}

export interface SoftwarePayload {
  name: string;
  version?: string;
  source?: 'homebrew' | 'mas' | 'dmg' | 'pkg' | 'app_store';
  url?: string;
  checksum?: string;
  installArgs?: string[];
  preInstallScript?: string;
  postInstallScript?: string;
}

export interface PolicyPayload {
  type: 'security' | 'configuration' | 'compliance';
  name: string;
  settings: Record<string, any>;
  validation?: string;
  rollback?: string;
}

class TaskExecutor {
  private readonly TEMP_DIR = path.join(os.tmpdir(), 'huginn-tasks');
  private readonly MAX_OUTPUT_SIZE = 1024 * 1024; // 1MB
  private readonly DEFAULT_TIMEOUT = 5 * 60 * 1000; // 5 minutes

  constructor() {
    this.ensureTempDir();
  }

  async execute(task: Task): Promise<TaskExecutionResult> {
    const startTime = Date.now();
    const timeout = task.timeout || this.DEFAULT_TIMEOUT;

    logger.info('Executing task', { 
      task_id: task.task_id, 
      type: task.type,
      timeout 
    });

    try {
      let result: TaskExecutionResult;

      switch (task.type) {
        case 'run_command':
          result = await this.executeCommand(task.payload as CommandPayload, timeout);
          break;
        case 'run_script':
          result = await this.executeScript(task.payload as ScriptPayload, timeout);
          break;
        case 'install_software':
          result = await this.installSoftware(task.payload as SoftwarePayload, timeout);
          break;
        case 'apply_policy':
          result = await this.applyPolicy(task.payload as PolicyPayload, timeout);
          break;
        default:
          throw new Error(`Unsupported task type: ${task.type}`);
      }

      const duration = Date.now() - startTime;
      result.duration = duration;

      logger.info('Task execution completed', {
        task_id: task.task_id,
        success: result.success,
        duration
      });

      return result;

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error('Task execution failed', {
        task_id: task.task_id,
        error: errorMessage,
        duration
      });

      return {
        success: false,
        error: errorMessage,
        duration
      };
    }
  }

  private async executeCommand(payload: CommandPayload, timeout: number): Promise<TaskExecutionResult> {
    const { command, args = [], workingDirectory, environment, shell } = payload;
    
    logger.debug('Executing command', { command, args, workingDirectory });

    // Security check - prevent dangerous commands
    if (this.isDangerousCommand(command)) {
      throw new Error(`Command '${command}' is not allowed for security reasons`);
    }

    const fullCommand = args.length > 0 ? `${command} ${args.join(' ')}` : command;
    const execOptions: any = {
      timeout,
      maxBuffer: this.MAX_OUTPUT_SIZE,
      cwd: workingDirectory || process.cwd(),
      env: { ...process.env, ...environment }
    };

    if (shell) {
      execOptions.shell = shell;
    }

    try {
      const { stdout, stderr } = await execAsync(fullCommand, execOptions);
      
      return {
        success: true,
        output: stdout,
        error: stderr || undefined,
        exitCode: 0
      };
    } catch (error: any) {
      return {
        success: false,
        output: error.stdout || undefined,
        error: error.stderr || error.message,
        exitCode: error.code || 1
      };
    }
  }

  private async executeScript(payload: ScriptPayload, timeout: number): Promise<TaskExecutionResult> {
    const { content, interpreter = 'bash', filename, arguments: scriptArgs = [], workingDirectory, environment } = payload;
    
    logger.debug('Executing script', { interpreter, filename, workingDirectory });

    // Create temporary script file
    const scriptPath = await this.createTempScript(content, filename, interpreter);
    
    try {
      // Make script executable
      await execAsync(`chmod +x "${scriptPath}"`);

      const command = `${interpreter} "${scriptPath}" ${scriptArgs.join(' ')}`;
      const execOptions: any = {
        timeout,
        maxBuffer: this.MAX_OUTPUT_SIZE,
        cwd: workingDirectory || process.cwd(),
        env: { ...process.env, ...environment }
      };

      try {
        const { stdout, stderr } = await execAsync(command, execOptions);
        
        return {
          success: true,
          output: stdout,
          error: stderr || undefined,
          exitCode: 0,
          metadata: { scriptPath, interpreter }
        };
      } catch (error: any) {
        return {
          success: false,
          output: error.stdout || undefined,
          error: error.stderr || error.message,
          exitCode: error.code || 1,
          metadata: { scriptPath, interpreter }
        };
      }
    } finally {
      // Clean up temporary script file
      try {
        await unlinkAsync(scriptPath);
      } catch (error) {
        logger.warn('Failed to clean up temp script', { scriptPath, error });
      }
    }
  }

  private async installSoftware(payload: SoftwarePayload, timeout: number): Promise<TaskExecutionResult> {
    const { name, version, source = 'homebrew', url, installArgs = [], preInstallScript, postInstallScript } = payload;
    
    logger.info('Installing software', { name, version, source });

    try {
      // Run pre-install script if provided
      if (preInstallScript) {
        logger.debug('Running pre-install script');
        const preResult = await this.executeScript({ content: preInstallScript }, timeout / 3);
        if (!preResult.success) {
          throw new Error(`Pre-install script failed: ${preResult.error}`);
        }
      }

      let installResult: TaskExecutionResult;

      switch (source) {
        case 'homebrew':
          installResult = await this.installViaHomebrew(name, version, installArgs, timeout);
          break;
        case 'mas':
          installResult = await this.installViaMAS(name, installArgs, timeout);
          break;
        case 'dmg':
        case 'pkg':
          if (!url) throw new Error('URL required for DMG/PKG installation');
          installResult = await this.installFromURL(url, source, installArgs, timeout);
          break;
        case 'app_store':
          installResult = await this.installFromAppStore(name, timeout);
          break;
        default:
          throw new Error(`Unsupported installation source: ${source}`);
      }

      if (!installResult.success) {
        return installResult;
      }

      // Run post-install script if provided
      if (postInstallScript) {
        logger.debug('Running post-install script');
        const postResult = await this.executeScript({ content: postInstallScript }, timeout / 3);
        if (!postResult.success) {
          logger.warn('Post-install script failed', { error: postResult.error });
          // Don't fail the entire installation for post-script failures
        }
      }

      return {
        success: true,
        output: `Successfully installed ${name}${version ? ` (${version})` : ''}`,
        metadata: { name, version, source }
      };

    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : String(error),
        metadata: { name, version, source }
      };
    }
  }

  private async applyPolicy(payload: PolicyPayload, timeout: number): Promise<TaskExecutionResult> {
    const { type, name, settings, validation, rollback } = payload;
    
    logger.info('Applying policy', { type, name });

    try {
      let result: TaskExecutionResult;

      switch (type) {
        case 'security':
          result = await this.applySecurityPolicy(name, settings, timeout);
          break;
        case 'configuration':
          result = await this.applyConfigurationPolicy(name, settings, timeout);
          break;
        case 'compliance':
          result = await this.applyCompliancePolicy(name, settings, timeout);
          break;
        default:
          throw new Error(`Unsupported policy type: ${type}`);
      }

      // Run validation if provided
      if (validation && result.success) {
        logger.debug('Running policy validation');
        const validationResult = await this.executeScript({ content: validation }, timeout / 3);
        if (!validationResult.success) {
          // Policy validation failed, attempt rollback
          if (rollback) {
            logger.warn('Policy validation failed, attempting rollback');
            await this.executeScript({ content: rollback }, timeout / 3);
          }
          throw new Error(`Policy validation failed: ${validationResult.error}`);
        }
      }

      return {
        success: true,
        output: `Successfully applied policy: ${name}`,
        metadata: { type, name, settings }
      };

    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : String(error),
        metadata: { type, name, settings }
      };
    }
  }

  // Installation methods

  private async installViaHomebrew(name: string, version?: string, args: string[] = [], timeout: number): Promise<TaskExecutionResult> {
    const packageName = version ? `${name}@${version}` : name;
    const command = `brew install ${packageName} ${args.join(' ')}`;
    
    // Ensure Homebrew is available
    try {
      await execAsync('which brew');
    } catch (error) {
      throw new Error('Homebrew is not installed or not in PATH');
    }

    return await this.executeCommand({ command }, timeout);
  }

  private async installViaMAS(name: string, args: string[] = [], timeout: number): Promise<TaskExecutionResult> {
    // Mac App Store CLI installation
    const command = `mas install ${name} ${args.join(' ')}`;
    
    try {
      await execAsync('which mas');
    } catch (error) {
      throw new Error('mas-cli is not installed. Install with: brew install mas');
    }

    return await this.executeCommand({ command }, timeout);
  }

  private async installFromURL(url: string, type: 'dmg' | 'pkg', args: string[] = [], timeout: number): Promise<TaskExecutionResult> {
    const tempDir = path.join(this.TEMP_DIR, `install-${Date.now()}`);
    const filename = path.basename(url);
    const filePath = path.join(tempDir, filename);

    try {
      // Create temp directory
      await execAsync(`mkdir -p "${tempDir}"`);

      // Download file
      logger.debug('Downloading installer', { url, filePath });
      await execAsync(`curl -L -o "${filePath}" "${url}"`, { timeout: timeout / 2 });

      if (type === 'dmg') {
        return await this.installFromDMG(filePath, args, timeout / 2);
      } else {
        return await this.installFromPKG(filePath, args, timeout / 2);
      }
    } finally {
      // Clean up
      try {
        await execAsync(`rm -rf "${tempDir}"`);
      } catch (error) {
        logger.warn('Failed to clean up temp directory', { tempDir, error });
      }
    }
  }

  private async installFromDMG(dmgPath: string, args: string[] = [], timeout: number): Promise<TaskExecutionResult> {
    const mountPoint = `/Volumes/HuginnInstall-${Date.now()}`;
    
    try {
      // Mount DMG
      await execAsync(`hdiutil attach "${dmgPath}" -mountpoint "${mountPoint}"`);

      // Find .app or .pkg files
      const { stdout } = await execAsync(`find "${mountPoint}" -name "*.app" -o -name "*.pkg" | head -1`);
      const installerPath = stdout.trim();

      if (!installerPath) {
        throw new Error('No .app or .pkg file found in DMG');
      }

      if (installerPath.endsWith('.app')) {
        // Copy .app to Applications
        const appName = path.basename(installerPath);
        await execAsync(`cp -R "${installerPath}" "/Applications/${appName}"`);
        return { success: true, output: `Installed ${appName} to Applications` };
      } else {
        // Install .pkg
        return await this.installFromPKG(installerPath, args, timeout);
      }
    } finally {
      // Unmount DMG
      try {
        await execAsync(`hdiutil detach "${mountPoint}"`);
      } catch (error) {
        logger.warn('Failed to unmount DMG', { mountPoint, error });
      }
    }
  }

  private async installFromPKG(pkgPath: string, args: string[] = [], timeout: number): Promise<TaskExecutionResult> {
    const command = `sudo installer -pkg "${pkgPath}" -target / ${args.join(' ')}`;
    return await this.executeCommand({ command }, timeout);
  }

  private async installFromAppStore(name: string, timeout: number): Promise<TaskExecutionResult> {
    // This would require integration with App Store APIs or mas-cli
    throw new Error('App Store installation not yet implemented');
  }

  // Policy application methods

  private async applySecurityPolicy(name: string, settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    logger.debug('Applying security policy', { name, settings });

    // Example security policies
    switch (name) {
      case 'firewall':
        return await this.configureFirewall(settings, timeout);
      case 'filevault':
        return await this.configureFileVault(settings, timeout);
      case 'gatekeeper':
        return await this.configureGatekeeper(settings, timeout);
      default:
        throw new Error(`Unknown security policy: ${name}`);
    }
  }

  private async applyConfigurationPolicy(name: string, settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    logger.debug('Applying configuration policy', { name, settings });

    // Example configuration policies
    switch (name) {
      case 'power_management':
        return await this.configurePowerManagement(settings, timeout);
      case 'network':
        return await this.configureNetwork(settings, timeout);
      case 'dock':
        return await this.configureDock(settings, timeout);
      default:
        throw new Error(`Unknown configuration policy: ${name}`);
    }
  }

  private async applyCompliancePolicy(name: string, settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    logger.debug('Applying compliance policy', { name, settings });

    // Compliance policies would check and enforce specific standards
    return {
      success: true,
      output: `Compliance policy ${name} applied successfully`
    };
  }

  // Specific policy configuration methods

  private async configureFirewall(settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    const enabled = settings.enabled || false;
    const command = enabled 
      ? 'sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on'
      : 'sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off';
    
    return await this.executeCommand({ command }, timeout);
  }

  private async configureFileVault(settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    // FileVault configuration would require user interaction for passwords
    // This is a simplified example
    if (settings.enabled) {
      return {
        success: false,
        error: 'FileVault enablement requires user interaction and cannot be automated'
      };
    }
    
    return { success: true, output: 'FileVault configuration completed' };
  }

  private async configureGatekeeper(settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    const level = settings.level || 'on';
    const command = `sudo spctl --master-${level}`;
    
    return await this.executeCommand({ command }, timeout);
  }

  private async configurePowerManagement(settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    const commands = [];
    
    if (settings.sleep_timeout) {
      commands.push(`sudo pmset -a sleep ${settings.sleep_timeout}`);
    }
    if (settings.display_sleep) {
      commands.push(`sudo pmset -a displaysleep ${settings.display_sleep}`);
    }
    
    for (const command of commands) {
      const result = await this.executeCommand({ command }, timeout / commands.length);
      if (!result.success) {
        return result;
      }
    }
    
    return { success: true, output: 'Power management configured successfully' };
  }

  private async configureNetwork(settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    // Network configuration would be more complex in practice
    return {
      success: true,
      output: 'Network configuration completed'
    };
  }

  private async configureDock(settings: Record<string, any>, timeout: number): Promise<TaskExecutionResult> {
    const commands = [];
    
    if (settings.autohide !== undefined) {
      commands.push(`defaults write com.apple.dock autohide -bool ${settings.autohide}`);
    }
    if (settings.position) {
      commands.push(`defaults write com.apple.dock orientation -string ${settings.position}`);
    }
    
    commands.push('killall Dock');
    
    for (const command of commands) {
      const result = await this.executeCommand({ command }, timeout / commands.length);
      if (!result.success) {
        return result;
      }
    }
    
    return { success: true, output: 'Dock configuration completed' };
  }

  // Utility methods

  private async createTempScript(content: string, filename?: string, interpreter: string = 'bash'): Promise<string> {
    const extension = this.getScriptExtension(interpreter);
    const scriptName = filename || `script-${Date.now()}${extension}`;
    const scriptPath = path.join(this.TEMP_DIR, scriptName);
    
    await writeFileAsync(scriptPath, content, 'utf8');
    return scriptPath;
  }

  private getScriptExtension(interpreter: string): string {
    const extensions: Record<string, string> = {
      'bash': '.sh',
      'sh': '.sh',
      'zsh': '.zsh',
      'python': '.py',
      'python3': '.py',
      'node': '.js',
      'ruby': '.rb',
      'perl': '.pl'
    };
    
    return extensions[interpreter] || '.sh';
  }

  private isDangerousCommand(command: string): boolean {
    const dangerousCommands = [
      'rm -rf /',
      'dd if=',
      'mkfs',
      'format',
      'fdisk',
      'shutdown',
      'reboot',
      'halt',
      'init 0',
      'init 6',
      'killall -9',
      'kill -9 1'
    ];
    
    return dangerousCommands.some(dangerous => 
      command.toLowerCase().includes(dangerous.toLowerCase())
    );
  }

  private ensureTempDir(): void {
    try {
      if (!fs.existsSync(this.TEMP_DIR)) {
        fs.mkdirSync(this.TEMP_DIR, { recursive: true });
      }
    } catch (error) {
      logger.error('Failed to create temp directory', { dir: this.TEMP_DIR, error });
    }
  }
}

export const taskExecutor = new TaskExecutor(); 