/**
 * Confirms the bearer token the iOS app forwarded really is a valid, current
 * Microsoft Graph access token by asking Graph who it belongs to. This is the
 * only gate keeping the legal assistant to signed-in Marite staff — reject
 * anything that doesn't resolve.
 */
export async function verifyCaller(authorizationHeader: string | null): Promise<{ id: string; displayName: string } | null> {
  if (!authorizationHeader?.startsWith("Bearer ")) return null;

  const response = await fetch("https://graph.microsoft.com/v1.0/me?$select=id,displayName", {
    headers: { Authorization: authorizationHeader }
  });

  if (!response.ok) return null;
  const json = (await response.json()) as { id: string; displayName: string };
  return json;
}
