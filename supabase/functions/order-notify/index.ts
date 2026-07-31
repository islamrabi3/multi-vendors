// Order push notifications, driven by database triggers.
//
// Called only by the `notify_order_event` trigger (pg_net), never by the app,
// so it authenticates with a shared secret instead of a user JWT. Running
// server-side means a vendor is told about a new order even when the
// customer's app is closed — which is always the case for card orders that
// settle through the Paymob webhook.
//
// Each recipient is messaged in the language they read the UI in
// (`profiles.locale`), because the server, not the app, composes the text.
//
// Request: { order_id, event }
//   new_order        -> the store owner
//   status_change    -> the customer
//   ready_for_pickup -> every online driver (a job is up for grabs)
//   driver_assigned  -> the assigned driver
//   order_cancelled  -> every admin
//
// Secrets required:
//   FIREBASE_SA_B64      — base64 of the service-account JSON
//   ORDER_NOTIFY_SECRET  — shared with the database trigger
import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

type Lang = "en" | "ar";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const TITLES: Record<string, Record<Lang, string>> = {
  new_order: { en: "New order! 🛒", ar: "طلب جديد! 🛒" },
  status_change: { en: "Order update 🚚", ar: "تحديث الطلب 🚚" },
  ready_for_pickup: { en: "Delivery available 🛵", ar: "طلب متاح للتوصيل 🛵" },
  driver_assigned: { en: "You got a delivery 🛵", ar: "تم تعيين توصيل لك 🛵" },
  order_cancelled: { en: "Order cancelled ⚠️", ar: "تم إلغاء طلب ⚠️" },
};

const STATUS_BODY: Record<string, Record<Lang, string>> = {
  accepted: {
    en: "Your order has been accepted by the store!",
    ar: "تم قبول طلبك من المتجر!",
  },
  preparing: {
    en: "Your order is being prepared in the kitchen!",
    ar: "جاري تحضير طلبك في المطبخ!",
  },
  ready_for_pickup: {
    en: "Your order is ready for pickup!",
    ar: "طلبك جاهز للاستلام!",
  },
  out_for_delivery: {
    en: "Your driver is on the way with your delivery! 🛵",
    ar: "السائق في الطريق إليك بطلبك! 🛵",
  },
  delivered: {
    en: "Your order has been delivered. Enjoy your meal! 🎉",
    ar: "تم تسليم طلبك. بالهنا والشفا! 🎉",
  },
  cancelled: {
    en: "Your order has been cancelled.",
    ar: "تم إلغاء طلبك.",
  },
  rejected: {
    en: "Your order was rejected by the store.",
    ar: "تم رفض طلبك من المتجر.",
  },
};

const STATUS_FALLBACK: Record<Lang, string> = {
  en: "Your order status has been updated.",
  ar: "تم تحديث حالة طلبك.",
};

function bodyFor(event: string, lang: Lang, status: string, label: string): string {
  switch (event) {
    case "new_order":
      return lang === "ar"
        ? `لديك طلب جديد ${label}`
        : `You have a new order ${label}`;
    case "ready_for_pickup":
      return lang === "ar"
        ? `طلب ${label} جاهز للاستلام — اقبله الآن`
        : `Order ${label} is ready for pickup — claim it now`;
    case "driver_assigned":
      return lang === "ar"
        ? `تم تعيين طلب ${label} لك`
        : `Order ${label} has been assigned to you`;
    case "order_cancelled":
      return lang === "ar"
        ? `تم إلغاء الطلب ${label}`
        : `Order ${label} was cancelled`;
    default:
      return STATUS_BODY[status]?.[lang] ?? STATUS_FALLBACK[lang];
  }
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
    const orderId = body.order_id;
    const event = `${body.event ?? ""}`;
    if (!orderId || !(event in TITLES)) {
      return json({ error: "INVALID_REQUEST" }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: order } = await admin
      .from("orders")
      .select(
        "id, order_number, status, customer_id, driver_id, vendors(owner_id)",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (!order) return json({ sent: 0, reason: "ORDER_NOT_FOUND" });

    // deno-lint-ignore no-explicit-any
    const ownerId = (order.vendors as any)?.owner_id as string | undefined;
    const label = order.order_number ?? `#${`${orderId}`.slice(0, 8)}`;
    const status = `${order.status}`;

    // Resolve recipients for this event.
    let targets: string[] = [];
    switch (event) {
      case "new_order":
        targets = ownerId ? [ownerId] : [];
        break;
      case "status_change":
        targets = order.customer_id ? [order.customer_id] : [];
        break;
      case "driver_assigned":
        targets = order.driver_id ? [order.driver_id] : [];
        break;
      case "ready_for_pickup": {
        const { data: drivers } = await admin
          .from("drivers")
          .select("id")
          .eq("is_online", true);
        targets = (drivers ?? []).map((d) => `${d.id}`);
        break;
      }
      case "order_cancelled": {
        const { data: admins } = await admin
          .from("profiles")
          .select("id")
          .eq("role", "admin");
        targets = (admins ?? []).map((a) => `${a.id}`);
        break;
      }
    }
    if (targets.length === 0) return json({ sent: 0, reason: "NO_RECIPIENT" });

    const { data: profiles } = await admin
      .from("profiles")
      .select("id, fcm_token, locale")
      .in("id", targets)
      .not("fcm_token", "is", null);

    const recipients = profiles ?? [];
    if (recipients.length === 0) return json({ sent: 0, reason: "NO_TOKEN" });

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
              notification: {
                title: TITLES[event][lang],
                body: bodyFor(event, lang, status, label),
              },
              data: { order_id: `${orderId}`, event, status },
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
      // Drop tokens Firebase reports as gone so we stop retrying them.
      if (fcmRes.status === 404 || fcmRes.status === 410) {
        stale.push(`${recipient.id}`);
      }
    }));

    if (stale.length > 0) {
      await admin.from("profiles")
        .update({ fcm_token: null })
        .in("id", stale);
    }

    console.log("pushed", event, orderId, "->", sent, "of", recipients.length);
    return json({ sent });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
