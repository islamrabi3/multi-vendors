// Chat push notifications, driven by the notify_chat_message trigger.
//
// An order carries two separate conversations: the customer with the store,
// and the customer with the rider. The recipients are whoever else is in the
// same conversation, so a message meant for the rider never reaches the store
// and vice versa. The body names the sender and the order so the notification
// is actionable from the lock screen, and the data payload carries the thread
// so the app opens the right conversation.
//
// Secrets required: FIREBASE_SA_B64, ORDER_NOTIFY_SECRET
import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

type Lang = "en" | "ar";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  try {
    const expectedSecret = Deno.env.get("ORDER_NOTIFY_SECRET");
    const saB64 = Deno.env.get("FIREBASE_SA_B64");
    if (!expectedSecret || !saB64) return json({ error: "NOT_CONFIGURED" }, 503);
    if (req.headers.get("x-notify-secret") !== expectedSecret) {
      return json({ error: "UNAUTHORIZED" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const messageId = body.message_id;
    if (!messageId) return json({ error: "INVALID_REQUEST" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: message } = await admin
      .from("chat_messages")
      .select("id, order_id, sender_id, message, image_url, thread")
      .eq("id", messageId)
      .maybeSingle();
    if (!message) return json({ sent: 0, reason: "MESSAGE_NOT_FOUND" });

    const thread = `${message.thread ?? "vendor"}` === "driver"
      ? "driver"
      : "vendor";

    const { data: order } = await admin
      .from("orders")
      .select("id, order_number, customer_id, driver_id, vendors(owner_id)")
      .eq("id", message.order_id)
      .maybeSingle();
    if (!order) return json({ sent: 0, reason: "ORDER_NOT_FOUND" });

    // deno-lint-ignore no-explicit-any
    const ownerId = (order.vendors as any)?.owner_id as string | undefined;
    const senderId = `${message.sender_id}`;

    // Only the other side of this conversation. The store never hears the
    // rider's thread, the rider never hears the store's.
    const audience = thread === "driver"
      ? [order.customer_id, order.driver_id]
      : [order.customer_id, ownerId];
    const target = audience.filter((id): id is string =>
      !!id && id !== senderId
    );
    if (target.length === 0) return json({ sent: 0, reason: "NO_RECIPIENT" });

    const { data: sender } = await admin
      .from("profiles")
      .select("full_name")
      .eq("id", senderId)
      .maybeSingle();

    const { data: profiles } = await admin
      .from("profiles")
      .select("id, fcm_token, locale")
      .in("id", target)
      .not("fcm_token", "is", null);

    const recipients = profiles ?? [];
    if (recipients.length === 0) return json({ sent: 0, reason: "NO_TOKEN" });

    const label = order.order_number ?? `#${`${order.id}`.slice(0, 8)}`;
    const preview = `${message.image_url ? "📷 " : ""}${
      `${message.message ?? ""}`.slice(0, 120)
    }`;

    const sa = JSON.parse(atob(saB64));
    const authClient = new JWT({
      email: sa.client_email,
      key: sa.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const { token: accessToken } = await authClient.getAccessToken();

    let sent = 0;
    const stale: string[] = [];

    await Promise.all(recipients.map(async (recipient) => {
      const lang: Lang = recipient.locale === "ar" ? "ar" : "en";
      const senderName = `${sender?.full_name ?? ""}`.trim() ||
        (lang === "ar" ? "مستخدم" : "Someone");
      // "Ahmed · Order ORD-123" tells the recipient who and about what
      // before they even unlock the phone.
      const title = lang === "ar"
        ? `${senderName} · طلب ${label}`
        : `${senderName} · ${label}`;

      const fcmRes = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            message: {
              token: recipient.fcm_token,
              notification: { title, body: preview },
              data: {
                type: "chat",
                order_id: `${order.id}`,
                thread,
                sender_id: senderId,
                sender_name: senderName,
              },
            },
          }),
        },
      );

      if (fcmRes.ok) {
        sent += 1;
        return;
      }
      const detail = await fcmRes.text();
      console.error("FCM send failed", fcmRes.status, detail);
      if (fcmRes.status === 404 || fcmRes.status === 410) {
        stale.push(`${recipient.id}`);
      }
    }));

    if (stale.length > 0) {
      await admin.from("profiles").update({ fcm_token: null }).in("id", stale);
    }

    console.log("chat push", messageId, thread, "->", sent, "of", recipients.length);
    return json({ sent, thread });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
