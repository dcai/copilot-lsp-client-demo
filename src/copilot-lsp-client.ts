import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { extname } from 'node:path';
import { pathToFileURL } from 'node:url';

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

type JsonRpcId = number;

type PendingRequest = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
};

export type LspPosition = {
  line: number;
  character: number;
};

export type InlineCompletionItem = {
  insertText: string;
  range: {
    start: LspPosition;
    end: LspPosition;
  };
  command?: {
    command: string;
    title?: string;
    arguments?: unknown[];
  };
};

export type InlineCompletionResponse = {
  items: InlineCompletionItem[];
};

export type StatusNotification = {
  busy: boolean;
  message: string;
  kind: 'Normal' | 'Error' | 'Warning' | 'Inactive' | string;
  command?: {
    command: string;
    title?: string;
    arguments?: unknown[];
  };
};

const createContentLengthHeader = (payload: string): string => {
  return `Content-Length: ${Buffer.byteLength(payload, 'utf8')}\r\n\r\n${payload}`;
};

const parseHeaders = (headerText: string): Map<string, string> => {
  return headerText
    .split('\r\n')
    .filter((line) => {
      return line.trim().length > 0;
    })
    .reduce((headers, line) => {
      const separatorIndex = line.indexOf(':');

      if (separatorIndex === -1) {
        return headers;
      }

      const key = line.slice(0, separatorIndex).trim().toLowerCase();
      const value = line.slice(separatorIndex + 1).trim();
      headers.set(key, value);
      return headers;
    }, new Map<string, string>());
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null;
};

const parseMessage = (value: unknown): string => {
  if (isRecord(value) && typeof value.message === 'string') {
    return value.message;
  }

  return JSON.stringify(value);
};

const detectLanguageId = (filePath: string): string => {
  const extension = extname(filePath).toLowerCase();

  if (extension === '.ts') {
    return 'typescript';
  }

  if (extension === '.md') {
    return 'markdown';
  }

  if (extension === '.sh') {
    return 'shellscript';
  }

  if (extension === '.yaml' || extension === '.yml') {
    return 'yaml';
  }

  return 'plaintext';
};

export class CopilotLspClient {
  private process: ChildProcessWithoutNullStreams;

  private nextId = 1;

  private buffer = Buffer.alloc(0);

  private readonly pendingRequests = new Map<JsonRpcId, PendingRequest>();

  private readonly notificationListeners = new Map<string, Array<(params: unknown) => void>>();

  private lastStatus: StatusNotification | null = null;

  public constructor() {
    this.process = spawn('node', ['./node_modules/@github/copilot-language-server/dist/language-server.js', '--stdio'], {
      stdio: 'pipe',
      env: process.env,
    });

    this.process.stdout.on('data', (chunk: Buffer) => {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      this.drainBuffer();
    });

    this.process.stderr.on('data', (chunk: Buffer) => {
      process.stderr.write(`[copilot-lsp stderr] ${chunk.toString('utf8')}`);
    });

    this.process.on('exit', (code, signal) => {
      const error = new Error(`Copilot LSP exited unexpectedly (code=${code ?? 'null'}, signal=${signal ?? 'null'})`);

      for (const [, pendingRequest] of this.pendingRequests) {
        pendingRequest.reject(error);
      }

      this.pendingRequests.clear();
    });
  }

  public onNotification(method: string, listener: (params: unknown) => void): void {
    const listeners = this.notificationListeners.get(method) ?? [];
    listeners.push(listener);
    this.notificationListeners.set(method, listeners);
  }

  public getLastStatus(): StatusNotification | null {
    return this.lastStatus;
  }

  public async initialize(workspacePath: string, editorVersion: string): Promise<void> {
    this.onNotification('didChangeStatus', (params) => {
      if (isRecord(params)) {
        this.lastStatus = params as StatusNotification;
      }
    });

    this.onNotification('window/logMessage', (params) => {
      process.stdout.write(`[window/logMessage] ${JSON.stringify(params)}\n`);
    });

    const workspaceUri = pathToFileURL(workspacePath).href;

    await this.request('initialize', {
      processId: process.pid,
      workspaceFolders: [{ uri: workspaceUri, name: 'workspace' }],
      capabilities: {
        workspace: {
          workspaceFolders: true,
          configuration: true,
        },
        window: {
          showDocument: {
            support: true,
          },
        },
      },
      initializationOptions: {
        editorInfo: {
          name: 'neovim',
          version: editorVersion,
        },
        editorPluginInfo: {
          name: 'copilot-lsp-client-neovim',
          version: '0.1.0',
        },
      },
    });

    this.notify('initialized', {});
    this.notify('workspace/didChangeConfiguration', {
      settings: {
        telemetry: {
          telemetryLevel: 'all',
        },
      },
    });
  }

  public async openDocument(filePath: string): Promise<{ uri: string; text: string; version: number }> {
    const text = readFileSync(filePath, 'utf8');
    const uri = pathToFileURL(filePath).href;
    const version = 1;

    this.notify('textDocument/didOpen', {
      textDocument: {
        uri,
        languageId: detectLanguageId(filePath),
        version,
        text,
      },
    });

    this.notify('textDocument/didFocus', {
      textDocument: {
        uri,
      },
    });

    return { uri, text, version };
  }

  public async requestInlineCompletion(input: {
    uri: string;
    version: number;
    position: LspPosition;
    triggerKind?: number;
  }): Promise<InlineCompletionResponse> {
    const response = await this.request('textDocument/inlineCompletion', {
      textDocument: {
        uri: input.uri,
        version: input.version,
      },
      position: input.position,
      context: {
        triggerKind: input.triggerKind ?? 2,
      },
      formattingOptions: {
        tabSize: 2,
        insertSpaces: true,
      },
    });

    return response as InlineCompletionResponse;
  }

  public notifyCompletionShown(item: InlineCompletionItem): void {
    this.notify('textDocument/didShowCompletion', { item });
  }

  public async acceptCompletion(item: InlineCompletionItem): Promise<void> {
    if (!item.command) {
      return;
    }

    await this.request('workspace/executeCommand', {
      command: item.command.command,
      arguments: item.command.arguments ?? [],
    });
  }

  public async signIn(): Promise<unknown> {
    return await this.request('signIn', {});
  }

  public async signOut(): Promise<unknown> {
    return await this.request('signOut', {});
  }

  public async executeCommand(command: { command: string; arguments?: unknown[] }): Promise<unknown> {
    return await this.request('workspace/executeCommand', {
      command: command.command,
      arguments: command.arguments ?? [],
    });
  }

  public async waitForStatus(timeoutMs: number): Promise<StatusNotification | null> {
    if (this.lastStatus) {
      return this.lastStatus;
    }

    return await new Promise((resolve) => {
      const timeout = setTimeout(() => {
        resolve(this.lastStatus);
      }, timeoutMs);

      this.onNotification('didChangeStatus', () => {
        if (this.lastStatus) {
          clearTimeout(timeout);
          resolve(this.lastStatus);
        }
      });
    });
  }

  public async close(): Promise<void> {
    for (const [id, pendingRequest] of this.pendingRequests) {
      pendingRequest.reject(new Error(`Client closed before request ${id} resolved`));
    }

    this.pendingRequests.clear();
    this.process.kill();
  }

  private async request(method: string, params: unknown): Promise<unknown> {
    const id = this.nextId;
    this.nextId += 1;

    const payload = {
      jsonrpc: '2.0',
      id,
      method,
      params,
    };

    return await new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });
      this.write(payload);
    });
  }

  private notify(method: string, params: unknown): void {
    this.write({
      jsonrpc: '2.0',
      method,
      params,
    });
  }

  private write(message: unknown): void {
    const payload = JSON.stringify(message);
    process.stdout.write(`[client -> server] ${payload}\n`);
    this.process.stdin.write(createContentLengthHeader(payload));
  }

  private drainBuffer(): void {
    while (true) {
      const separator = this.buffer.indexOf('\r\n\r\n');

      if (separator === -1) {
        return;
      }

      const headerText = this.buffer.subarray(0, separator).toString('utf8');
      const headers = parseHeaders(headerText);
      const contentLength = Number(headers.get('content-length'));

      if (!Number.isFinite(contentLength)) {
        throw new Error(`Invalid content-length header: ${headers.get('content-length') ?? 'missing'}`);
      }

      const messageStart = separator + 4;
      const messageEnd = messageStart + contentLength;

      if (this.buffer.length < messageEnd) {
        return;
      }

      const body = this.buffer.subarray(messageStart, messageEnd).toString('utf8');
      this.buffer = this.buffer.subarray(messageEnd);
      const message = JSON.parse(body) as Record<string, unknown>;
      process.stdout.write(`[server -> client] ${JSON.stringify(message)}\n`);
      this.handleMessage(message);
    }
  }

  private handleMessage(message: Record<string, unknown>): void {
    if (typeof message.id === 'number' && Object.prototype.hasOwnProperty.call(message, 'result')) {
      const pendingRequest = this.pendingRequests.get(message.id);

      if (!pendingRequest) {
        return;
      }

      this.pendingRequests.delete(message.id);
      pendingRequest.resolve(message.result);
      return;
    }

    if (typeof message.id === 'number' && Object.prototype.hasOwnProperty.call(message, 'error')) {
      const pendingRequest = this.pendingRequests.get(message.id);

      if (!pendingRequest) {
        return;
      }

      this.pendingRequests.delete(message.id);
      pendingRequest.reject(new Error(parseMessage(message.error)));
      return;
    }

    if (typeof message.method === 'string' && Object.prototype.hasOwnProperty.call(message, 'id')) {
      this.handleServerRequest(message.method, message.id as number, message.params);
      return;
    }

    if (typeof message.method === 'string') {
      const listeners = this.notificationListeners.get(message.method) ?? [];

      for (const listener of listeners) {
        listener(message.params);
      }
    }
  }

  private handleServerRequest(method: string, id: number, params: unknown): void {
    if (method === 'window/showDocument' && isRecord(params) && typeof params.uri === 'string') {
      const uri = params.uri;
      const openCommand = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
      spawn(openCommand, [uri], { stdio: 'ignore', shell: process.platform === 'win32' });
      this.write({ jsonrpc: '2.0', id, result: { success: true } });
      return;
    }

    this.write({ jsonrpc: '2.0', id, result: null });
  }
}
