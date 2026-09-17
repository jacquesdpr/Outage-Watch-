import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { verifyCaller } from "../lib/callerIdentity";
import { getDeviceTokens } from "../lib/deviceTokenStore";
import { sendPushToAll } from "../lib/apnsClient";

interface RequestBody {
  assignedToId: string;
  channelId: string;
  channelName: string;
  messageId: string;
  taskItemId: string;
  taskSummary: string;
}

/**
 * Called by the tagging user's app right after it creates a StaffTask (see
 * ChatService.sendTaskMessage on the iOS side). Looks up the tagged person's
 * registered devices and pushes a "you've been tagged" alert to each.
 *
 * This is a best-effort, client-triggered notification, not a guaranteed
 * delivery pipeline: if the tagger's device loses connectivity right after
 * the Graph call succeeds, the push won't fire even though the task exists.
 * The task itself is always visible next time the assignee opens the app
 * (via My Tasks / the channel), so nothing is lost — just possibly not
 * announced immediately. See docs/ARCHITECTURE.md for the more robust
 * (webhook-based) alternative if that gap matters for a given scheme.
 */
app.http("notifyTagged", {
  methods: ["POST"],
  authLevel: "anonymous",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const caller = await verifyCaller(request.headers.get("authorization"));
    if (!caller) {
      return { status: 401, jsonBody: { error: "Sign in with your Marite Microsoft 365 account and try again." } };
    }

    let body: RequestBody;
    try {
      body = (await request.json()) as RequestBody;
    } catch {
      return { status: 400, jsonBody: { error: "Invalid request body." } };
    }

    if (!body.assignedToId || !body.channelId || !body.messageId) {
      return { status: 400, jsonBody: { error: "assignedToId, channelId, and messageId are required." } };
    }

    // No point pushing to yourself if you tag yourself as a reminder.
    if (body.assignedToId === caller.id) {
      return { status: 204 };
    }

    try {
      const deviceTokens = await getDeviceTokens(body.assignedToId);
      if (deviceTokens.length === 0) {
        return { status: 204 };
      }

      await sendPushToAll(body.assignedToId, deviceTokens, {
        title: `${caller.displayName} tagged you in #${body.channelName}`,
        body: body.taskSummary,
        data: {
          type: "task",
          channelId: body.channelId,
          messageId: body.messageId,
          taskItemId: body.taskItemId
        }
      });

      return { status: 204 };
    } catch (error) {
      context.error("notifyTagged failed", error);
      return { status: 500, jsonBody: { error: "Could not send the notification." } };
    }
  }
});
