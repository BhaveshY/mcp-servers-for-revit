import * as net from "net";

type PendingResponse = {
  resolve: (response: unknown) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
  command: string;
};

export type RevitConnectionOptions = {
  host?: string;
  port?: number;
  connectTimeoutMs?: number;
  commandTimeoutMs?: number;
};

export class RevitClientConnection {
  readonly host: string;
  readonly port: number;
  readonly connectTimeoutMs: number;
  readonly commandTimeoutMs: number;

  private socket: net.Socket | null = null;
  private connectPromise: Promise<void> | null = null;
  private responseCallbacks: Map<string, PendingResponse> = new Map();
  private buffer = "";

  isConnected = false;

  constructor(host: string, port: number, options: RevitConnectionOptions = {}) {
    this.host = host;
    this.port = port;
    this.connectTimeoutMs = options.connectTimeoutMs ?? 5000;
    this.commandTimeoutMs = options.commandTimeoutMs ?? 120000;
  }

  async connect(): Promise<void> {
    if (this.isConnected && this.socket && !this.socket.destroyed) {
      return;
    }

    if (this.connectPromise) {
      return this.connectPromise;
    }

    this.socket?.destroy();
    this.socket = new net.Socket();
    this.setupSocketListeners(this.socket);

    this.connectPromise = new Promise<void>((resolve, reject) => {
      const socket = this.socket;
      if (!socket) {
        reject(new Error("Socket was not initialized"));
        return;
      }

      const timeout = setTimeout(() => {
        cleanup();
        socket.destroy();
        reject(
          new Error(
            `Timed out connecting to Revit bridge at ${this.host}:${this.port}`
          )
        );
      }, this.connectTimeoutMs);

      const cleanup = () => {
        clearTimeout(timeout);
        socket.removeListener("connect", onConnect);
        socket.removeListener("error", onError);
        this.connectPromise = null;
      };

      const onConnect = () => {
        cleanup();
        this.isConnected = true;
        resolve();
      };

      const onError = (error: Error) => {
        cleanup();
        this.isConnected = false;
        reject(
          new Error(
            `Failed to connect to Revit bridge at ${this.host}:${this.port}: ${error.message}`
          )
        );
      };

      socket.once("connect", onConnect);
      socket.once("error", onError);
      socket.connect(this.port, this.host);
    });

    return this.connectPromise;
  }

  disconnect(): void {
    this.socket?.end();
    this.socket?.destroy();
    this.socket = null;
    this.isConnected = false;
    this.connectPromise = null;
    this.rejectPendingResponses(
      new Error("Disconnected from Revit bridge before a response was received")
    );
  }

  async sendCommand(command: string, params: unknown = {}): Promise<any> {
    await this.connect();

    const socket = this.socket;
    if (!socket || socket.destroyed || !this.isConnected) {
      throw new Error("Revit bridge socket is not connected");
    }

    const requestId = this.generateRequestId();
    const commandObj = {
      jsonrpc: "2.0",
      method: command,
      params,
      id: requestId,
    };

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.responseCallbacks.delete(requestId);
        reject(
          new Error(
            `Command timed out after ${this.commandTimeoutMs}ms: ${command}`
          )
        );
      }, this.commandTimeoutMs);

      this.responseCallbacks.set(requestId, {
        resolve,
        reject,
        timer,
        command,
      });

      socket.write(JSON.stringify(commandObj), (error) => {
        if (!error) {
          return;
        }

        this.clearPendingResponse(requestId);
        reject(
          new Error(
            `Failed to send command "${command}" to Revit bridge: ${error.message}`
          )
        );
      });
    });
  }

  private setupSocketListeners(socket: net.Socket): void {
    socket.setKeepAlive(true, 30000);

    socket.on("data", (data) => {
      if (socket !== this.socket) {
        return;
      }

      this.buffer += data.toString("utf8");
      try {
        this.processBuffer();
      } catch (error) {
        this.buffer = "";
        this.rejectPendingResponses(
          error instanceof Error ? error : new Error(String(error))
        );
      }
    });

    socket.on("close", () => {
      if (socket !== this.socket) {
        return;
      }

      this.isConnected = false;
      this.connectPromise = null;
      this.rejectPendingResponses(
        new Error("Revit bridge connection closed before responding")
      );
    });

    socket.on("error", (error) => {
      if (socket !== this.socket) {
        return;
      }

      this.isConnected = false;
      this.connectPromise = null;
      this.rejectPendingResponses(
        new Error(`Revit bridge socket error: ${error.message}`)
      );
    });
  }

  private processBuffer(): void {
    let message: string | null;

    while ((message = this.extractJsonMessage()) !== null) {
      this.handleResponse(message);
    }
  }

  private extractJsonMessage(): string | null {
    let start = -1;
    let depth = 0;
    let inString = false;
    let isEscaped = false;

    for (let i = 0; i < this.buffer.length; i++) {
      const current = this.buffer[i];

      if (start < 0) {
        if (/\s/.test(current)) {
          continue;
        }

        if (current !== "{") {
          const invalid = this.buffer.slice(0, i + 1);
          this.buffer = this.buffer.slice(i + 1);
          throw new Error(`Invalid JSON-RPC response prefix: ${invalid}`);
        }

        start = i;
        depth = 1;
        continue;
      }

      if (isEscaped) {
        isEscaped = false;
        continue;
      }

      if (current === "\\" && inString) {
        isEscaped = true;
        continue;
      }

      if (current === "\"") {
        inString = !inString;
        continue;
      }

      if (inString) {
        continue;
      }

      if (current === "{") {
        depth++;
      } else if (current === "}") {
        depth--;
        if (depth === 0) {
          const message = this.buffer.slice(start, i + 1);
          this.buffer = this.buffer.slice(i + 1);
          return message;
        }
      }
    }

    return null;
  }

  private handleResponse(responseData: string): void {
    let response: any;

    try {
      response = JSON.parse(responseData);
    } catch (error) {
      console.error("Error parsing Revit bridge response:", error);
      return;
    }

    const requestId = String(response.id ?? "default");
    const pending = this.responseCallbacks.get(requestId);
    if (!pending) {
      return;
    }

    this.clearPendingResponse(requestId);

    if (response.error) {
      pending.reject(
        new Error(
          response.error.message || `Unknown Revit error in ${pending.command}`
        )
      );
      return;
    }

    pending.resolve(response.result);
  }

  private clearPendingResponse(requestId: string): void {
    const pending = this.responseCallbacks.get(requestId);
    if (!pending) {
      return;
    }

    clearTimeout(pending.timer);
    this.responseCallbacks.delete(requestId);
  }

  private rejectPendingResponses(error: Error): void {
    for (const [requestId, pending] of this.responseCallbacks.entries()) {
      clearTimeout(pending.timer);
      pending.reject(error);
      this.responseCallbacks.delete(requestId);
    }
  }

  private generateRequestId(): string {
    return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  }
}
