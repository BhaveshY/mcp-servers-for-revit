import { RevitClientConnection } from "./SocketClient.js";

export const CONNECT_RETRY_DELAYS_MS = [1000, 2000, 4000];
const CONNECT_TIMEOUT_MS = 5000;
const RECOVERY_HINT =
  "In Revit: Add-Ins > mcp-servers-for-revit > Stop, then Start. If Revit is frozen, wait for it to recover before retrying.";

// Mutex to serialize all Revit connections - prevents race conditions
// when multiple requests are made in parallel
let connectionMutex: Promise<void> = Promise.resolve();

/**
 * Connect to the Revit plugin and execute an operation.
 */
export async function withRevitConnection<T>(
  operation: (client: RevitClientConnection) => Promise<T>
): Promise<T> {
  // Wait for any pending connection to complete before starting a new one
  const previousMutex = connectionMutex;
  let releaseMutex!: () => void;
  connectionMutex = new Promise<void>((resolve) => {
    releaseMutex = resolve;
  });
  await previousMutex;

  let revitClient: RevitClientConnection | undefined;

  try {
    revitClient = await connectWithRetry();
    return await operation(revitClient);
  } finally {
    revitClient?.disconnect();
    // Release the mutex so the next request can proceed
    releaseMutex();
  }
}

async function connectWithRetry(): Promise<RevitClientConnection> {
  let lastError: unknown;

  for (let attempt = 0; attempt <= CONNECT_RETRY_DELAYS_MS.length; attempt++) {
    const revitClient = new RevitClientConnection("localhost", 8080);

    try {
      await connectOnce(revitClient);
      return revitClient;
    } catch (error) {
      lastError = error;
      revitClient.disconnect();

      const delay = CONNECT_RETRY_DELAYS_MS[attempt];
      if (delay !== undefined) {
        await sleep(delay);
      }
    }
  }

  const lastMessage = lastError instanceof Error ? lastError.message : String(lastError);
  throw new Error(
    `connect_to_revit_failed: Could not connect to the Revit MCP plugin on localhost:8080 ` +
      `after ${CONNECT_RETRY_DELAYS_MS.length + 1} attempts. Recovery: ${RECOVERY_HINT} ` +
      `Last error: ${lastMessage}`
  );
}

function connectOnce(revitClient: RevitClientConnection): Promise<void> {
  if (revitClient.isConnected) {
    return Promise.resolve();
  }

  return new Promise<void>((resolve, reject) => {
    let settled = false;
    const cleanup = () => {
      clearTimeout(timeout);
      revitClient.socket.removeListener("connect", onConnect);
      revitClient.socket.removeListener("error", onError);
    };

    const finish = (callback: () => void) => {
      if (settled) return;
      settled = true;
      cleanup();
      callback();
    };

    const onConnect = () => finish(resolve);
    const onError = (error: Error) =>
      finish(() => reject(new Error(`socket_error: ${error.message}`)));

    const timeout = setTimeout(() => {
      revitClient.socket.destroy();
      finish(() => reject(new Error(`socket_timeout_after_${CONNECT_TIMEOUT_MS}ms`)));
    }, CONNECT_TIMEOUT_MS);

    revitClient.socket.on("connect", onConnect);
    revitClient.socket.on("error", onError);

    if (!revitClient.connect()) {
      finish(() => reject(new Error("socket_connect_call_failed")));
    }
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
