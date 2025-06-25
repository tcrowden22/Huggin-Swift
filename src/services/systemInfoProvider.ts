import { exec } from 'child_process';
import { promisify } from 'util';
import * as os from 'os';
import { logger } from '../utils/logger';

const execAsync = promisify(exec);

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

export interface SystemMetrics {
  cpu: {
    model: string;
    cores: number;
    usage: number;
    temperature?: number;
  };
  memory: {
    total: number;
    used: number;
    free: number;
    usage: number;
  };
  disk: Array<{
    device: string;
    mountpoint: string;
    size: number;
    used: number;
    available: number;
    usage: number;
    filesystem: string;
  }>;
  network: {
    interfaces: Array<{
      name: string;
      address: string;
      netmask: string;
      family: string;
      mac: string;
      internal: boolean;
    }>;
    usage: {
      bytesReceived: number;
      bytesSent: number;
      packetsReceived: number;
      packetsSent: number;
    };
  };
  uptime: number;
  loadAverage: number[];
}

class SystemInfoProvider {
  async getDeviceInfo(): Promise<DeviceInfo> {
    try {
      const hostname = os.hostname();
      const platform = os.platform();
      const arch = os.arch();
      const version = os.release();
      const cpus = os.cpus();
      const totalMemory = os.totalmem();
      
      // Get primary network interface MAC address
      const networkInterfaces = os.networkInterfaces();
      let macAddress = '';
      
      for (const [name, interfaces] of Object.entries(networkInterfaces)) {
        if (interfaces && !name.includes('lo') && !name.includes('Loopback')) {
          const primaryInterface = interfaces.find(iface => 
            !iface.internal && iface.family === 'IPv4'
          );
          if (primaryInterface?.mac) {
            macAddress = primaryInterface.mac;
            break;
          }
        }
      }

      let serialNumber: string | undefined;
      
      // Get serial number (macOS specific)
      if (platform === 'darwin') {
        try {
          const { stdout } = await execAsync('system_profiler SPHardwareDataType | grep "Serial Number" | awk \'{print $4}\'');
          serialNumber = stdout.trim();
        } catch (error) {
          logger.warn('Failed to get serial number', error);
        }
      }

      return {
        hostname,
        platform,
        arch,
        version,
        cpuModel: cpus[0]?.model || 'Unknown',
        totalMemory,
        macAddress,
        serialNumber
      };
    } catch (error) {
      logger.error('Failed to get device info', error);
      throw error;
    }
  }

  async getSystemMetrics(): Promise<SystemMetrics> {
    try {
      const cpuInfo = await this.getCPUInfo();
      const memoryInfo = await this.getMemoryInfo();
      const diskInfo = await this.getDiskInfo();
      const networkInfo = await this.getNetworkInfo();

      return {
        cpu: cpuInfo,
        memory: memoryInfo,
        disk: diskInfo,
        network: networkInfo,
        uptime: os.uptime(),
        loadAverage: os.loadavg()
      };
    } catch (error) {
      logger.error('Failed to get system metrics', error);
      throw error;
    }
  }

  private async getCPUInfo() {
    const cpus = os.cpus();
    let usage = 0;
    let temperature: number | undefined;

    // Calculate CPU usage
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('top -l 1 -n 0 | grep "CPU usage" | awk \'{print $3}\' | sed \'s/%//\'');
        usage = parseFloat(stdout.trim()) || 0;
      } else if (os.platform() === 'linux') {
        const { stdout } = await execAsync('top -bn1 | grep "Cpu(s)" | awk \'{print $2}\' | sed \'s/%us,//\'');
        usage = parseFloat(stdout.trim()) || 0;
      }
    } catch (error) {
      logger.warn('Failed to get CPU usage', error);
    }

    // Get CPU temperature (macOS)
    if (os.platform() === 'darwin') {
      try {
        const { stdout } = await execAsync('sudo powermetrics -n 1 -s cpu_power | grep "CPU die temperature" | awk \'{print $4}\'');
        temperature = parseFloat(stdout.trim());
      } catch (error) {
        // Temperature monitoring might require sudo, so it's optional
        logger.debug('Failed to get CPU temperature', error);
      }
    }

    return {
      model: cpus[0]?.model || 'Unknown',
      cores: cpus.length,
      usage,
      temperature
    };
  }

  private async getMemoryInfo() {
    const totalMemory = os.totalmem();
    const freeMemory = os.freemem();
    const usedMemory = totalMemory - freeMemory;
    const usage = (usedMemory / totalMemory) * 100;

    return {
      total: totalMemory,
      used: usedMemory,
      free: freeMemory,
      usage
    };
  }

  private async getDiskInfo() {
    const diskInfo: any[] = [];

    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('df -h | grep -E "^/dev/"');
        const lines = stdout.trim().split('\n');
        
        for (const line of lines) {
          const parts = line.split(/\s+/);
          if (parts.length >= 6) {
            const size = this.parseSize(parts[1]);
            const used = this.parseSize(parts[2]);
            const available = this.parseSize(parts[3]);
            const usage = parseFloat(parts[4].replace('%', ''));

            diskInfo.push({
              device: parts[0],
              mountpoint: parts[5],
              size,
              used,
              available,
              usage,
              filesystem: 'APFS' // Default for macOS
            });
          }
        }
      } else if (os.platform() === 'linux') {
        const { stdout } = await execAsync('df -h -x tmpfs -x devtmpfs');
        const lines = stdout.trim().split('\n').slice(1); // Skip header
        
        for (const line of lines) {
          const parts = line.split(/\s+/);
          if (parts.length >= 6) {
            const size = this.parseSize(parts[1]);
            const used = this.parseSize(parts[2]);
            const available = this.parseSize(parts[3]);
            const usage = parseFloat(parts[4].replace('%', ''));

            diskInfo.push({
              device: parts[0],
              mountpoint: parts[5],
              size,
              used,
              available,
              usage,
              filesystem: 'ext4' // Common default
            });
          }
        }
      }
    } catch (error) {
      logger.warn('Failed to get disk info', error);
    }

    return diskInfo;
  }

  private async getNetworkInfo() {
    const networkInterfaces = os.networkInterfaces();
    const interfaces: any[] = [];
    
    for (const [name, interfaceList] of Object.entries(networkInterfaces)) {
      if (interfaceList) {
        for (const iface of interfaceList) {
          interfaces.push({
            name,
            address: iface.address,
            netmask: iface.netmask,
            family: iface.family,
            mac: iface.mac,
            internal: iface.internal
          });
        }
      }
    }

    // Get network usage statistics
    let usage = {
      bytesReceived: 0,
      bytesSent: 0,
      packetsReceived: 0,
      packetsSent: 0
    };

    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('netstat -ib | grep -E "en[0-9]" | head -1');
        const parts = stdout.trim().split(/\s+/);
        if (parts.length >= 10) {
          usage = {
            bytesReceived: parseInt(parts[6]) || 0,
            bytesSent: parseInt(parts[9]) || 0,
            packetsReceived: parseInt(parts[4]) || 0,
            packetsSent: parseInt(parts[7]) || 0
          };
        }
      }
    } catch (error) {
      logger.warn('Failed to get network usage', error);
    }

    return {
      interfaces,
      usage
    };
  }

  private parseSize(sizeStr: string): number {
    const units: { [key: string]: number } = {
      'B': 1,
      'K': 1024,
      'M': 1024 * 1024,
      'G': 1024 * 1024 * 1024,
      'T': 1024 * 1024 * 1024 * 1024
    };

    const match = sizeStr.match(/^(\d+(?:\.\d+)?)(B|K|M|G|T)?$/i);
    if (!match) return 0;

    const value = parseFloat(match[1]);
    const unit = (match[2] || 'B').toUpperCase();
    
    return value * (units[unit] || 1);
  }

  // macOS specific methods
  async getMacOSSystemInfo() {
    if (os.platform() !== 'darwin') return null;

    try {
      const commands = [
        'system_profiler SPSoftwareDataType',
        'system_profiler SPHardwareDataType',
        'system_profiler SPMemoryDataType',
        'system_profiler SPStorageDataType'
      ];

      const results = await Promise.all(
        commands.map(cmd => execAsync(cmd).catch(err => ({ stdout: '', stderr: err.message })))
      );

      return {
        software: results[0].stdout,
        hardware: results[1].stdout,
        memory: results[2].stdout,
        storage: results[3].stdout
      };
    } catch (error) {
      logger.error('Failed to get macOS system info', error);
      return null;
    }
  }

  async getSecurityInfo() {
    const securityInfo: any = {
      firewall: { enabled: false, status: 'unknown' },
      antivirus: { installed: false, products: [] },
      encryption: { enabled: false, type: 'none' },
      updates: { available: 0, lastCheck: null }
    };

    try {
      if (os.platform() === 'darwin') {
        // Check firewall status
        try {
          const { stdout: firewallStatus } = await execAsync('sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate');
          securityInfo.firewall.enabled = firewallStatus.includes('enabled');
          securityInfo.firewall.status = firewallStatus.trim();
        } catch (error) {
          logger.warn('Failed to check firewall status', error);
        }

        // Check FileVault encryption
        try {
          const { stdout: fvStatus } = await execAsync('fdesetup status');
          securityInfo.encryption.enabled = fvStatus.includes('On');
          securityInfo.encryption.type = 'FileVault';
        } catch (error) {
          logger.warn('Failed to check FileVault status', error);
        }

        // Check for software updates
        try {
          const { stdout: updateList } = await execAsync('softwareupdate -l');
          const updates = updateList.split('\n').filter(line => line.includes('*'));
          securityInfo.updates.available = updates.length;
          securityInfo.updates.lastCheck = new Date().toISOString();
        } catch (error) {
          logger.warn('Failed to check software updates', error);
        }
      }
    } catch (error) {
      logger.error('Failed to get security info', error);
    }

    return securityInfo;
  }
}

export const systemInfoProvider = new SystemInfoProvider(); 