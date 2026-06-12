// Paymob "transaction processed" webhook. Public endpoint (verify_jwt off);
// authenticity is established by the HMAC-SHA512 signature Paymob sends as a
// query parameter, computed over a fixed, lexicographically-ordered field list.
//
// Secrets required: PAYMOB_HMAC_SECRET
import { createClient } from "npm:@supabase/supabase-js@2";

// deno-lint-ignore no-explicit-any
function hmacFieldValues(obj: any): string {
  // Field order is defined by Paymob's docs and must not change.
  const values = [
    obj.amount_cents,
    obj.created_at,
    obj.currency,
    obj.error_occured,
    obj.has_parent_transaction,
    obj.id,
    obj.integration_id,
    obj.is_3d_secure,
    obj.is_auth,
    obj.is_capture,
    obj.is_refunded,
    obj.is_standalone_payment,
    obj.is_voided,
    obj.order?.id,
    obj.owner,
    obj.pending,
    obj.source_data?.pan,
    obj.source_data?.sub_type,
    obj.source_data?.type,
    obj.success,
  ];
  return values.map((v) => `${v}`).join("");
}

async function computeHmac(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const hmacSecret = Deno.env.get("PAYMOB_HMAC_SECRET");
    if (!hmacSecret) {
      return new Response("PAYMOB_NOT_CONFIGURED", { status: 503 });
    }

    const url = new URL(req.url);
    const receivedHmac = url.searchParams.get("hmac");
    const payload = await req.json();
    const tx = payload.obj;

    if (!receivedHmac || !tx) {
      return new Response("Bad request", { status: 400 });
    }

    const expectedHmac = await computeHmac(hmacFieldValues(tx), hmacSecret);
    if (expectedHmac !== receivedHmac) {
      console.error("HMAC mismatch for transaction", tx.id);
      return new Response("Invalid signature", { status: 401 });
    }

    // special_reference was "<order_uuid>:<timestamp>".
    const merchantOrderId: string = tx.order?.merchant_order_id ?? "";
    const orderId = merchantOrderId.split(":")[0];
    if (!orderId) {
      console.error("No merchant_order_id on transaction", tx.id);
      return new Response("ok", { status: 200 });
    }

    const paid = tx.success === true && tx.pending !== true;
    const status = paid ? "paid" : "failed";

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    await admin.from("payments").insert({
      order_id: orderId,
      provider: "paymob",
      amount: Number(tx.amount_cents ?? 0) / 100,
      status,
      provider_transaction_id: `${tx.id}`,
      provider_order_id: `${tx.order?.id ?? ""}`,
      raw_payload: tx,
    });

    // Never downgrade an order that is already paid (e.g. duplicate callback).
    const { data: order } = await admin
      .from("orders")
      .select("payment_status")
      .eq("id", orderId)
      .single();

    if (order && order.payment_status !== "paid") {
      await admin
        .from("orders")
        .update({ payment_status: status })
        .eq("id", orderId);
    }

    return new Response("ok", { status: 200 });
  } catch (error) {
    console.error(error);
    return new Response("Internal error", { status: 500 });
  }
});
