import http2 from "node:http2";
import jwt from "jsonwebtoken";
import { requireEnv } from "./graphAuth";
import { unregisterDeviceToken } from "./deviceTokenStore";

export interface PushPayload {
  title: string;
  body: string;
  /** Arbitrary extra fields delivered alongside `aps`, used for deep-linking on tap. */
  data: Record<string, string>;
}

let cachedAuthToken: { value: string; issuedAt: number } | null = null;

/** APNs provider tokens are meant to be reused for up to ~an hour, not minted per push. */
function getAuthToken(): string {
  const oneHourMs = 60 * 60 * 1000;
  if (cachedAuthToken && Date.now() - cachedAuthToken.issuedAt < oneHourMs - 5 * 60 * 1000) {
    return cachedAuthToken.value;
  }

  const keyId = requireEnv("APNS_KEY_ID");
  const teamId = requireEnv("APNS_TEAM_ID");
  // Azure App Settings can't store real newlines cleanly; the key is stored
  // with literal "\n" sequences and unescaped here.
  const privateKey = requireEnv("APNS_AUTH_KEY").replace(/\\n/g, "\n");

  const token = jwt.sign({ iss: teamId, iat: Math.floor(Date.now() / 1000) }, privateKey, {
    algorithm: "ES256",
    header: { alg: "ES256", kid: keyId }
  });

  cachedAuthToken = { value: token, issuedAt: Date.now() };
  return token;
}

function apnsHost(): string {
  const environment = process.env.APNS_ENVIRONMENT ?? "development";
  return environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
}

/**
 * Sends one push to one device token. Resolves even on failure (never throws)
 * so a bad/expired token for one of a user's devices can't stop the push to
 * their other devices — instead it prunes tokens APNs reports as gone.
 */
export async function sendPush(userId: string, deviceToken: string, payload: PushPayload): Promise<void> {
  const bundleId = requireEnv("APNS_BUNDLE_ID");
  const client = http2.connect(apnsHost());

  try {
    await new Promise<void>((resolve) => {
      const request = client.request({
        ":method": "POST",
        ":path": `/3/device/${deviceToken}`,
        authorization: `bearer ${getAuthToken()}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json"
      });

      let status = 0;
      request.on("response", (headers) => {
        status = Number(headers[":status"] ?? 0);
      });

      let responseBody = "";
      request.on("data", (chunk) => {
        responseBody += chunk;
      });

      request.on("end", async () => {
        if (status === 400 || status === 410) {
          // BadDeviceToken / Unregistered — the token is dead, stop using it.
          await unregisterDeviceToken(userId, deviceToken).catch(() => undefined);
        } else if (status && status !== 200) {
          console.error(`APNs push failed (status ${status}): ${responseBody}`);
        }
        resolve();
      });

      request.on("error", (error) => {
        console.error("APNs request error", error);
        resolve();
      });

      request.end(
        JSON.stringify({
          aps: { alert: { title: payload.title, body: payload.body }, sound: "default" },
          ...payload.data
        })
      );
    });
  } finally {
    client.close();
  }
}

export async function sendPushToAll(userId: string, deviceTokens: string[], payload: PushPayload): Promise<void> {
  await Promise.all(deviceTokens.map((token) => sendPush(userId, token, payload)));
}
