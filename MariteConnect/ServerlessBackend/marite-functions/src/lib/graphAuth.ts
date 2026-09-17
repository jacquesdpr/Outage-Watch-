/**
 * App-only (client credentials) Microsoft Graph auth, used ONLY to read the
 * shared Sectional Title Legal Library — a library every staff member should be
 * able to search regardless of their own SharePoint permissions on other sites.
 *
 * The caller's own delegated token (forwarded from the iOS app) is validated
 * separately in callerIdentity.ts before any of this runs, so this app-only
 * token never gets used on behalf of an unverified caller.
 */

let cachedToken: { value: string; expiresAt: number } | null = null;

export async function getAppOnlyGraphToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 30_000) {
    return cachedToken.value;
  }

  const tenantId = requireEnv("GRAPH_TENANT_ID");
  const clientId = requireEnv("GRAPH_CLIENT_ID");
  const clientSecret = requireEnv("GRAPH_CLIENT_SECRET");

  const response = await fetch(`https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "client_credentials",
      scope: "https://graph.microsoft.com/.default"
    })
  });

  if (!response.ok) {
    throw new Error(`Failed to acquire app-only Graph token: ${response.status} ${await response.text()}`);
  }

  const json = (await response.json()) as { access_token: string; expires_in: number };
  cachedToken = { value: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cachedToken.value;
}

export function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}
