import { exec } from 'child_process';
import { promisify } from 'util';
import * as os from 'os';
import * as fs from 'fs';
import { systemInfoProvider } from './systemInfoProvider';
import { logger } from '../utils/logger';

const execAsync = promisify(exec);
const readFileAsync = promisify(fs.readFile);

export interface TelemetryData {
  hardware: HardwareTelemetry;
  software: SoftwareTelemetry;
  security: SecurityTelemetry;
  network: NetworkTelemetry;
  policies: PolicyTelemetry;
  performance: PerformanceTelemetry;
  timestamp: string;
  agentVersion: string;
}

export interface HardwareTelemetry {
  cpu: {
    model: string;
    cores: number;
    architecture: string;
    frequency?: number;
    usage: number;
    temperature?: number;
  };
  memory: {
    total: number;
    used: number;
    free: number;
    usage: number;
    swapTotal?: number;
    swapUsed?: number;
  };
  storage: Array<{
    device: string;
    type: 'HDD' | 'SSD' | 'Unknown';
    size: number;
    used: number;
    available: number;
    usage: number;
    filesystem: string;
    mountpoint: string;
    health?: string;
  }>;
  gpu: Array<{
    model: string;
    vendor: string;
    memory?: number;
    driver?: string;
  }>;
  usb: Array<{
    device: string;
    vendor: string;
    product: string;
    serial?: string;
  }>;
  network: Array<{
    interface: string;
    type: 'Ethernet' | 'WiFi' | 'Bluetooth' | 'Other';
    mac: string;
    speed?: number;
    status: 'Connected' | 'Disconnected' | 'Unknown';
  }>;
}

export interface SoftwareTelemetry {
  os: {
    name: string;
    version: string;
    build?: string;
    kernel: string;
    architecture: string;
  };
  installedApps: Array<{
    name: string;
    version: string;
    vendor?: string;
    installDate?: string;
    size?: number;
    location?: string;
  }>;
  services: Array<{
    name: string;
    status: 'Running' | 'Stopped' | 'Unknown';
    startType?: 'Auto' | 'Manual' | 'Disabled';
    pid?: number;
  }>;
  processes: Array<{
    name: string;
    pid: number;
    cpu: number;
    memory: number;
    user: string;
    command?: string;
  }>;
}

export interface SecurityTelemetry {
  antivirus: {
    installed: boolean;
    products: Array<{
      name: string;
      version?: string;
      status: 'Active' | 'Inactive' | 'Unknown';
      lastUpdate?: string;
    }>;
  };
  firewall: {
    enabled: boolean;
    status: string;
    rules?: number;
  };
  encryption: {
    diskEncryption: {
      enabled: boolean;
      type?: string;
      status?: string;
    };
    bitlocker?: {
      enabled: boolean;
      status?: string;
    };
  };
  updates: {
    available: number;
    pending: number;
    lastCheck?: string;
    lastInstall?: string;
    autoUpdate: boolean;
  };
  vulnerabilities: Array<{
    id: string;
    severity: 'Critical' | 'High' | 'Medium' | 'Low';
    description: string;
    affected?: string;
  }>;
}

export interface NetworkTelemetry {
  interfaces: Array<{
    name: string;
    type: string;
    mac: string;
    ip: string;
    subnet: string;
    gateway?: string;
    dns?: string[];
    status: string;
  }>;
  connections: Array<{
    protocol: string;
    localAddress: string;
    localPort: number;
    remoteAddress?: string;
    remotePort?: number;
    state: string;
    process?: string;
  }>;
  usage: {
    bytesReceived: number;
    bytesSent: number;
    packetsReceived: number;
    packetsSent: number;
    errors: number;
    drops: number;
  };
  wifi?: {
    ssid: string;
    signal: number;
    security: string;
    frequency: number;
  };
}

export interface PolicyTelemetry {
  applied: Array<{
    id: string;
    name: string;
    type: string;
    status: 'Applied' | 'Failed' | 'Pending';
    lastApplied?: string;
    version?: string;
  }>;
  compliance: {
    score: number;
    total: number;
    failed: Array<{
      policy: string;
      reason: string;
      severity: string;
    }>;
  };
}

export interface PerformanceTelemetry {
  uptime: number;
  loadAverage: number[];
  bootTime?: string;
  systemLoad: {
    cpu: number;
    memory: number;
    disk: number;
    network: number;
  };
  alerts: Array<{
    type: string;
    message: string;
    severity: string;
    timestamp: string;
  }>;
}

class TelemetryCollector {
  private readonly AGENT_VERSION = '1.0.0';

  async collect(): Promise<TelemetryData> {
    logger.info('Starting telemetry collection');
    
    try {
      const [
        hardware,
        software,
        security,
        network,
        policies,
        performance
      ] = await Promise.all([
        this.collectHardwareTelemetry(),
        this.collectSoftwareTelemetry(),
        this.collectSecurityTelemetry(),
        this.collectNetworkTelemetry(),
        this.collectPolicyTelemetry(),
        this.collectPerformanceTelemetry()
      ]);

      const telemetryData: TelemetryData = {
        hardware,
        software,
        security,
        network,
        policies,
        performance,
        timestamp: new Date().toISOString(),
        agentVersion: this.AGENT_VERSION
      };

      logger.info('Telemetry collection completed successfully');
      return telemetryData;
    } catch (error) {
      logger.error('Failed to collect telemetry', error);
      throw error;
    }
  }

  private async collectHardwareTelemetry(): Promise<HardwareTelemetry> {
    const systemMetrics = await systemInfoProvider.getSystemMetrics();
    
    // Get GPU information
    const gpu = await this.getGPUInfo();
    
    // Get USB devices
    const usb = await this.getUSBDevices();
    
    // Enhance storage information with health data
    const enhancedStorage = await Promise.all(
      systemMetrics.disk.map(async (disk) => ({
        device: disk.device,
        type: await this.getStorageType(disk.device),
        size: disk.size,
        used: disk.used,
        available: disk.available,
        usage: disk.usage,
        filesystem: disk.filesystem,
        mountpoint: disk.mountpoint,
        health: await this.getStorageHealth(disk.device)
      }))
    );

    // Enhanced network interfaces
    const networkInterfaces = systemMetrics.network.interfaces.map(iface => ({
      interface: iface.name,
      type: this.getNetworkType(iface.name),
      mac: iface.mac,
      speed: undefined, // Could be enhanced with speed detection
      status: iface.internal ? 'Unknown' : 'Connected' as const
    }));

    return {
      cpu: {
        model: systemMetrics.cpu.model,
        cores: systemMetrics.cpu.cores,
        architecture: os.arch(),
        usage: systemMetrics.cpu.usage,
        temperature: systemMetrics.cpu.temperature
      },
      memory: {
        total: systemMetrics.memory.total,
        used: systemMetrics.memory.used,
        free: systemMetrics.memory.free,
        usage: systemMetrics.memory.usage
      },
      storage: enhancedStorage,
      gpu,
      usb,
      network: networkInterfaces
    };
  }

  private async collectSoftwareTelemetry(): Promise<SoftwareTelemetry> {
    const osInfo = {
      name: os.platform(),
      version: os.release(),
      kernel: os.release(),
      architecture: os.arch()
    };

    const [installedApps, services, processes] = await Promise.all([
      this.getInstalledApplications(),
      this.getSystemServices(),
      this.getRunningProcesses()
    ]);

    return {
      os: osInfo,
      installedApps,
      services,
      processes
    };
  }

  private async collectSecurityTelemetry(): Promise<SecurityTelemetry> {
    const securityInfo = await systemInfoProvider.getSecurityInfo();
    
    return {
      antivirus: {
        installed: securityInfo.antivirus.installed,
        products: securityInfo.antivirus.products
      },
      firewall: {
        enabled: securityInfo.firewall.enabled,
        status: securityInfo.firewall.status
      },
      encryption: {
        diskEncryption: {
          enabled: securityInfo.encryption.enabled,
          type: securityInfo.encryption.type
        }
      },
      updates: {
        available: securityInfo.updates.available,
        pending: 0,
        lastCheck: securityInfo.updates.lastCheck,
        autoUpdate: false // Could be enhanced with actual detection
      },
      vulnerabilities: [] // Could be enhanced with vulnerability scanning
    };
  }

  private async collectNetworkTelemetry(): Promise<NetworkTelemetry> {
    const systemMetrics = await systemInfoProvider.getSystemMetrics();
    
    const interfaces = systemMetrics.network.interfaces.map(iface => ({
      name: iface.name,
      type: iface.family,
      mac: iface.mac,
      ip: iface.address,
      subnet: iface.netmask,
      status: iface.internal ? 'Loopback' : 'Active'
    }));

    const connections = await this.getNetworkConnections();
    const wifiInfo = await this.getWiFiInfo();

    return {
      interfaces,
      connections,
      usage: systemMetrics.network.usage,
      wifi: wifiInfo
    };
  }

  private async collectPolicyTelemetry(): Promise<PolicyTelemetry> {
    // This would be enhanced based on actual policy management system
    return {
      applied: [],
      compliance: {
        score: 100,
        total: 100,
        failed: []
      }
    };
  }

  private async collectPerformanceTelemetry(): Promise<PerformanceTelemetry> {
    const systemMetrics = await systemInfoProvider.getSystemMetrics();
    
    return {
      uptime: systemMetrics.uptime,
      loadAverage: systemMetrics.loadAverage,
      systemLoad: {
        cpu: systemMetrics.cpu.usage,
        memory: systemMetrics.memory.usage,
        disk: systemMetrics.disk[0]?.usage || 0,
        network: 0 // Could be calculated from network usage
      },
      alerts: [] // Could be enhanced with system alerts
    };
  }

  // Helper methods for enhanced data collection

  private async getGPUInfo(): Promise<Array<any>> {
    const gpus: Array<any> = [];
    
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('system_profiler SPDisplaysDataType -json');
        const data = JSON.parse(stdout);
        
        if (data.SPDisplaysDataType) {
          for (const gpu of data.SPDisplaysDataType) {
            gpus.push({
              model: gpu.sppci_model || 'Unknown',
              vendor: gpu.sppci_vendor || 'Unknown',
              memory: gpu.spdisplays_vram ? parseInt(gpu.spdisplays_vram) : undefined
            });
          }
        }
      }
    } catch (error) {
      logger.warn('Failed to get GPU info', error);
    }
    
    return gpus;
  }

  private async getUSBDevices(): Promise<Array<any>> {
    const devices: Array<any> = [];
    
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('system_profiler SPUSBDataType -json');
        const data = JSON.parse(stdout);
        
        if (data.SPUSBDataType) {
          for (const hub of data.SPUSBDataType) {
            if (hub._items) {
              for (const device of hub._items) {
                devices.push({
                  device: device._name || 'Unknown',
                  vendor: device.vendor_id || 'Unknown',
                  product: device.product_id || 'Unknown',
                  serial: device.serial_num
                });
              }
            }
          }
        }
      }
    } catch (error) {
      logger.warn('Failed to get USB devices', error);
    }
    
    return devices;
  }

  private async getStorageType(device: string): Promise<'HDD' | 'SSD' | 'Unknown'> {
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync(`diskutil info ${device} | grep "Solid State"`);
        return stdout.includes('Yes') ? 'SSD' : 'HDD';
      }
    } catch (error) {
      logger.debug('Failed to determine storage type', error);
    }
    
    return 'Unknown';
  }

  private async getStorageHealth(device: string): Promise<string | undefined> {
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync(`diskutil verifyVolume ${device}`);
        return stdout.includes('appears to be OK') ? 'Good' : 'Warning';
      }
    } catch (error) {
      logger.debug('Failed to get storage health', error);
    }
    
    return undefined;
  }

  private getNetworkType(interfaceName: string): 'Ethernet' | 'WiFi' | 'Bluetooth' | 'Other' {
    if (interfaceName.startsWith('en') && !interfaceName.includes('w')) {
      return 'Ethernet';
    } else if (interfaceName.includes('wi') || interfaceName.includes('wl')) {
      return 'WiFi';
    } else if (interfaceName.includes('bt') || interfaceName.includes('bluetooth')) {
      return 'Bluetooth';
    }
    return 'Other';
  }

  private async getInstalledApplications(): Promise<Array<any>> {
    const apps: Array<any> = [];
    
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('system_profiler SPApplicationsDataType -json');
        const data = JSON.parse(stdout);
        
        if (data.SPApplicationsDataType) {
          for (const app of data.SPApplicationsDataType) {
            apps.push({
              name: app._name || 'Unknown',
              version: app.version || 'Unknown',
              vendor: app.info || undefined,
              location: app.path || undefined
            });
          }
        }
      }
    } catch (error) {
      logger.warn('Failed to get installed applications', error);
    }
    
    return apps;
  }

  private async getSystemServices(): Promise<Array<any>> {
    const services: Array<any> = [];
    
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('launchctl list');
        const lines = stdout.split('\n').slice(1); // Skip header
        
        for (const line of lines) {
          const parts = line.trim().split(/\s+/);
          if (parts.length >= 3) {
            services.push({
              name: parts[2],
              status: parts[0] !== '-' ? 'Running' : 'Stopped',
              pid: parts[0] !== '-' ? parseInt(parts[0]) : undefined
            });
          }
        }
      }
    } catch (error) {
      logger.warn('Failed to get system services', error);
    }
    
    return services;
  }

  private async getRunningProcesses(): Promise<Array<any>> {
    const processes: Array<any> = [];
    
    try {
      const { stdout } = await execAsync('ps -eo pid,pcpu,pmem,user,comm --no-headers | head -20');
      const lines = stdout.split('\n');
      
      for (const line of lines) {
        const parts = line.trim().split(/\s+/);
        if (parts.length >= 5) {
          processes.push({
            pid: parseInt(parts[0]),
            cpu: parseFloat(parts[1]),
            memory: parseFloat(parts[2]),
            user: parts[3],
            name: parts[4]
          });
        }
      }
    } catch (error) {
      logger.warn('Failed to get running processes', error);
    }
    
    return processes;
  }

  private async getNetworkConnections(): Promise<Array<any>> {
    const connections: Array<any> = [];
    
    try {
      const { stdout } = await execAsync('netstat -an | head -20');
      const lines = stdout.split('\n').slice(2); // Skip headers
      
      for (const line of lines) {
        const parts = line.trim().split(/\s+/);
        if (parts.length >= 6) {
          const [localAddr, localPort] = parts[3].split(':');
          const [remoteAddr, remotePort] = parts[4].split(':');
          
          connections.push({
            protocol: parts[0],
            localAddress: localAddr || '',
            localPort: parseInt(localPort) || 0,
            remoteAddress: remoteAddr || undefined,
            remotePort: remotePort ? parseInt(remotePort) : undefined,
            state: parts[5]
          });
        }
      }
    } catch (error) {
      logger.warn('Failed to get network connections', error);
    }
    
    return connections;
  }

  private async getWiFiInfo(): Promise<any> {
    try {
      if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I');
        const lines = stdout.split('\n');
        const wifiInfo: any = {};
        
        for (const line of lines) {
          const [key, value] = line.trim().split(': ');
          if (key && value) {
            wifiInfo[key.trim()] = value.trim();
          }
        }
        
        return {
          ssid: wifiInfo.SSID || 'Unknown',
          signal: parseInt(wifiInfo.agrCtlRSSI) || 0,
          security: wifiInfo.link_auth || 'Unknown',
          frequency: parseInt(wifiInfo.channel) || 0
        };
      }
    } catch (error) {
      logger.debug('Failed to get WiFi info', error);
    }
    
    return undefined;
  }
}

export const telemetryCollector = new TelemetryCollector(); 