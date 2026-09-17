import { TableClient, TableServiceClient } from "@azure/data-tables";

/**
 * Registered iOS device push tokens, keyed by the Entra ID user's object ID.
 * Stored in Azure Table Storage on the same storage account the Function App
 * already requires for AzureWebJobsStorage — no separate database to
 * provision just to remember which device belongs to which staff member.
 *
 * One user can have several rows (phone + iPad, or a reinstalled app before
 * the old token is pruned by APNs feedback) — notifyTagged pushes to all of
 * them.
 */
const TABLE_NAME = "DeviceTokens";

interface DeviceTokenEntity {
  partitionKey: string; // Entra ID user object ID
  rowKey: string; // APNs device token (hex)
  displayName: string;
  updatedAt: string;
}

let tableClientPromise: Promise<TableClient> | null = null;

async function getTableClient(): Promise<TableClient> {
  if (!tableClientPromise) {
    tableClientPromise = (async () => {
      const connectionString = requireConnectionString();
      const serviceClient = TableServiceClient.fromConnectionString(connectionString);
      await serviceClient.createTable(TABLE_NAME).catch((error) => {
        // 409 = table already exists, which is the expected steady state.
        if (error.statusCode !== 409) throw error;
      });
      return TableClient.fromConnectionString(connectionString, TABLE_NAME);
    })();
  }
  return tableClientPromise;
}

function requireConnectionString(): string {
  const value = process.env.AzureWebJobsStorage;
  if (!value) throw new Error("Missing required environment variable: AzureWebJobsStorage");
  return value;
}

export async function registerDeviceToken(userId: string, displayName: string, deviceToken: string): Promise<void> {
  const client = await getTableClient();
  const entity: DeviceTokenEntity = {
    partitionKey: userId,
    rowKey: deviceToken,
    displayName,
    updatedAt: new Date().toISOString()
  };
  await client.upsertEntity(entity, "Replace");
}

export async function unregisterDeviceToken(userId: string, deviceToken: string): Promise<void> {
  const client = await getTableClient();
  await client.deleteEntity(userId, deviceToken).catch((error) => {
    if (error.statusCode !== 404) throw error;
  });
}

export async function getDeviceTokens(userId: string): Promise<string[]> {
  const client = await getTableClient();
  const tokens: string[] = [];
  for await (const entity of client.listEntities<DeviceTokenEntity>({ queryOptions: { filter: `PartitionKey eq '${userId}'` } })) {
    tokens.push(entity.rowKey);
  }
  return tokens;
}
