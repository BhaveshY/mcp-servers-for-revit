import * as net from "net";
import { RevitClientConnection } from "./SocketClient.js";

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 8080;
const DEFAULT_CONNECT_TIMEOUT_MS = 5000;
const DEFAULT_COMMAND_TIMEOUT_MS = 120000;

const host = process.env.REVIT_MCP_HOST || DEFAULT_HOST;
const port = parseIntegerEnv("REVIT_MCP_PORT", DEFAULT_PORT);
const connectTimeoutMs = parseIntegerEnv(
  "REVIT_MCP_CONNECT_TIMEOUT_MS",
  DEFAULT_CONNECT_TIMEOUT_MS
);
const commandTimeoutMs = parseIntegerEnv(
  "REVIT_MCP_COMMAND_TIMEOUT_MS",
  DEFAULT_COMMAND_TIMEOUT_MS
);

let connectionMutex: Promise<void> = Promise.resolve();
let sharedClient: RevitClientConnection | null = null;

export type RevitBridgeStatus = {
  connected: boolean;
  host: string;
  port: number;
  latencyMs?: number;
  error?: string;
};

export async function withRevitConnection<T>(
  operation: (client: RevitClientConnection) => Promise<T>
): Promise<T> {
  const previousMutex = connectionMutex;
  let releaseMutex!: () => void;
  connectionMutex = new Promise<void>((resolve) => {
    releaseMutex = resolve;
  });

  await previousMutex;

  try {
    const revitClient = getSharedClient();
    await revitClient.connect();
    return await operation(revitClient);
  } catch (error) {
    if (sharedClient && !sharedClient.isConnected) {
      sharedClient.disconnect();
      sharedClient = null;
    }
    throw error;
  } finally {
    releaseMutex();
  }
}

export async function getRevitBridgeStatus(): Promise<RevitBridgeStatus> {
  const startedAt = Date.now();

  return new Promise((resolve) => {
    const socket = new net.Socket();
    const timeout = setTimeout(() => {
      socket.destroy();
      resolve({
        connected: false,
        host,
        port,
        error: `Timed out after ${connectTimeoutMs}ms`,
      });
    }, connectTimeoutMs);

    const finish = (status: RevitBridgeStatus) => {
      clearTimeout(timeout);
      socket.removeAllListeners();
      socket.destroy();
      resolve(status);
    };

    socket.once("connect", () => {
      finish({
        connected: true,
        host,
        port,
        latencyMs: Date.now() - startedAt,
      });
    });

    socket.once("error", (error) => {
      finish({
        connected: false,
        host,
        port,
        error: error.message,
      });
    });

    socket.connect(port, host);
  });
}

export function closeRevitConnection(): void {
  sharedClient?.disconnect();
  sharedClient = null;
}

function getSharedClient(): RevitClientConnection {
  if (!sharedClient) {
    sharedClient = new RevitClientConnection(host, port, {
      connectTimeoutMs,
      commandTimeoutMs,
    });
  }

  return sharedClient;
}

function parseIntegerEnv(name: string, fallback: number): number {
  const rawValue = process.env[name];
  if (!rawValue) {
    return fallback;
  }

  const parsed = Number.parseInt(rawValue, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
