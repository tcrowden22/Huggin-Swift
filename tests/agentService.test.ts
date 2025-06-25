import { AgentService } from '../src/services/agentService';

// Mock dependencies
jest.mock('keytar');
jest.mock('../src/services/systemInfoProvider');
jest.mock('../src/services/telemetryCollector');
jest.mock('../src/services/taskExecutor');
jest.mock('../src/utils/logger');

// Mock fetch
global.fetch = jest.fn();

describe('AgentService', () => {
  let agentService: AgentService;

  beforeEach(() => {
    jest.clearAllMocks();
    agentService = new AgentService({
      baseUrl: 'https://test.supabase.co/functions/v1',
      serviceName: 'test-huginn-agent',
      pollInterval: 1000,
      telemetryInterval: 5000,
      maxRetries: 2
    });
  });

  afterEach(async () => {
    if (agentService) {
      await agentService.stop();
    }
  });

  describe('Token Management', () => {
    test('should handle token refresh logic', async () => {
      const mockFetch = global.fetch as jest.MockedFunction<typeof fetch>;
      
      mockFetch.mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({
          access_token: 'new-token',
          expires_at: Date.now() + 60000
        })
      } as Response);

      const refreshed = await agentService.forceTokenRefresh();
      expect(typeof refreshed).toBe('boolean');
    });

    test('should report authentication status', () => {
      const status = agentService.getStatus();
      expect(status).toHaveProperty('authenticated');
      expect(status).toHaveProperty('running');
      expect(status).toHaveProperty('agentId');
      expect(status).toHaveProperty('tokenExpiry');
    });
  });

  describe('Service Lifecycle', () => {
    test('should start and stop service', async () => {
      let startedEmitted = false;
      let stoppedEmitted = false;

      agentService.on('started', () => {
        startedEmitted = true;
      });

      agentService.on('stopped', () => {
        stoppedEmitted = true;
      });

      await agentService.start();
      expect(startedEmitted).toBe(true);

      await agentService.stop();
      expect(stoppedEmitted).toBe(true);
    });

    test('should provide status information', () => {
      const status = agentService.getStatus();
      expect(status.running).toBe(false);
      expect(status.authenticated).toBe(false);
      expect(status.agentId).toBeNull();
    });
  });

  describe('Public Methods', () => {
    test('should provide agent ID when available', () => {
      const agentId = agentService.getAgentId();
      expect(agentId).toBeNull();
    });

    test('should check authentication status', () => {
      const authenticated = agentService.isAuthenticated();
      expect(authenticated).toBe(false);
    });

    test('should force telemetry report', async () => {
      await expect(agentService.forceTelemetryReport()).resolves.not.toThrow();
    });
  });
}); 