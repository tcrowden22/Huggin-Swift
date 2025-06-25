import { taskExecutor } from '../src/services/taskExecutor';
import type { Task } from '../src/services/taskExecutor';

// Mock child_process
jest.mock('child_process');
jest.mock('../src/utils/logger');

describe('TaskExecutor', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Task Execution', () => {
    test('should handle run_command tasks', async () => {
      const task: Task = {
        task_id: 'test-command-1',
        type: 'run_command',
        payload: {
          command: 'echo',
          args: ['hello', 'world']
        },
        priority: 1,
        created_at: new Date().toISOString()
      };

      const result = await taskExecutor.execute(task);
      
      expect(result).toHaveProperty('success');
      expect(result).toHaveProperty('duration');
      expect(typeof result.success).toBe('boolean');
      expect(typeof result.duration).toBe('number');
    });

    test('should handle run_script tasks', async () => {
      const task: Task = {
        task_id: 'test-script-1',
        type: 'run_script',
        payload: {
          content: '#!/bin/bash\necho "Hello from script"',
          interpreter: 'bash'
        },
        priority: 1,
        created_at: new Date().toISOString()
      };

      const result = await taskExecutor.execute(task);
      
      expect(result).toHaveProperty('success');
      expect(result).toHaveProperty('duration');
      expect(result.metadata).toHaveProperty('interpreter', 'bash');
    });

    test('should handle install_software tasks', async () => {
      const task: Task = {
        task_id: 'test-install-1',
        type: 'install_software',
        payload: {
          name: 'test-package',
          source: 'homebrew'
        },
        priority: 1,
        created_at: new Date().toISOString()
      };

      const result = await taskExecutor.execute(task);
      
      expect(result).toHaveProperty('success');
      expect(result).toHaveProperty('duration');
      expect(result.metadata).toHaveProperty('name', 'test-package');
    });

    test('should handle apply_policy tasks', async () => {
      const task: Task = {
        task_id: 'test-policy-1',
        type: 'apply_policy',
        payload: {
          type: 'security',
          name: 'firewall',
          settings: { enabled: true }
        },
        priority: 1,
        created_at: new Date().toISOString()
      };

      const result = await taskExecutor.execute(task);
      
      expect(result).toHaveProperty('success');
      expect(result).toHaveProperty('duration');
      expect(result.metadata).toHaveProperty('type', 'security');
    });

    test('should handle unsupported task types', async () => {
      const task: Task = {
        task_id: 'test-unsupported-1',
        type: 'unsupported_type' as any,
        payload: {},
        priority: 1,
        created_at: new Date().toISOString()
      };

      const result = await taskExecutor.execute(task);
      
      expect(result.success).toBe(false);
      expect(result.error).toContain('Unsupported task type');
    });

    test('should respect task timeout', async () => {
      const task: Task = {
        task_id: 'test-timeout-1',
        type: 'run_command',
        payload: {
          command: 'sleep',
          args: ['10']
        },
        priority: 1,
        timeout: 100, // 100ms timeout
        created_at: new Date().toISOString()
      };

      const startTime = Date.now();
      const result = await taskExecutor.execute(task);
      const duration = Date.now() - startTime;
      
      // Should complete within reasonable time due to timeout
      expect(duration).toBeLessThan(5000);
      expect(result).toHaveProperty('duration');
    });
  });

  describe('Security', () => {
    test('should reject dangerous commands', async () => {
      const dangerousTask: Task = {
        task_id: 'test-dangerous-1',
        type: 'run_command',
        payload: {
          command: 'rm -rf /'
        },
        priority: 1,
        created_at: new Date().toISOString()
      };

      const result = await taskExecutor.execute(dangerousTask);
      
      expect(result.success).toBe(false);
      expect(result.error).toContain('not allowed for security reasons');
    });
  });
}); 