// Runs every tool's real SQL, as a real `authenticated` admin, against a
// throwaway Postgres. Skipped unless ADMIN_MCP_TEST_DB_URL is set:
//
//   docker run -d --rm --name admin_mcp_smoke -e POSTGRES_PASSWORD=smoke \
//     -p 127.0.0.1:55432:5432 postgres:15
//   ADMIN_MCP_TEST_DB_URL=postgres://postgres:smoke@127.0.0.1:55432/postgres \
//     deno test --allow-env --allow-net --allow-read smoke_test.ts
//
// It builds its own database from testing/stub_schema.sql plus the real
// admin_mcp_tokens migration, and refuses to run anywhere but localhost.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import postgres from "npm:postgres@3.4.5";

import { describeFailure } from "./protocol.ts";
import { authenticate, callAs } from "./session.ts";
import { type Accounts, type Caller, ToolError, tools } from "./tools.ts";

const URL_ENV = Deno.env.get("ADMIN_MCP_TEST_DB_URL");
const DATABASE = "admin_mcp_smoke";

const OWNER = "00000000-0000-4000-8000-000000000001";
const SUPPORT = "00000000-0000-4000-8000-000000000002";
const PENDING_DRIVER = "00000000-0000-4000-8000-000000000005";
const ACTIVE_DRIVER = "00000000-0000-4000-8000-000000000006";
const PENDING_STORE = "b0000000-0000-4000-8000-000000000001";
const ACTIVE_STORE = "b0000000-0000-4000-8000-000000000002";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const ORDER = "d0000000-0000-4000-8000-000000000001";
const COMPLAINT = "e0000000-0000-4000-8000-000000000001";
const THREAD = "f0000000-0000-4000-8000-000000000001";
const AREA = "99999999-0000-4000-8000-000000000001";

const here = (path: string) => new URL(path, import.meta.url);

async function freshDatabase(): Promise<postgres.Sql> {
  const target = new URL(URL_ENV!);
  if (!["127.0.0.1", "localhost"].includes(target.hostname)) {
    throw new Error("smoke_test only runs against a local database");
  }
  const admin = postgres(URL_ENV!, { max: 1, onnotice: () => {} });
  await admin.unsafe(`drop database if exists ${DATABASE} with (force)`);
  await admin.unsafe(`create database ${DATABASE}`);
  await admin.end();

  target.pathname = `/${DATABASE}`;
  const sql = postgres(target.href, { max: 4, prepare: false, onnotice: () => {} });
  await sql.unsafe(await Deno.readTextFile(here("./testing/stub_schema.sql")));
  await sql.unsafe(
    await Deno.readTextFile(
      here("../../migrations/20261003190225_admin_mcp_tokens.sql"),
    ),
  );
  return sql;
}

/// Makes a key the way the dashboard does: signed in as the admin.
async function createKey(sql: postgres.Sql, adminId: string, name: string) {
  return await sql.begin(async (tx) => {
    await tx.unsafe("select set_config('request.jwt.claims', $1::text, true)", [
      JSON.stringify({ sub: adminId, role: "authenticated" }),
    ]);
    await tx.unsafe("set local role authenticated");
    const rows = await tx.unsafe(
      "select public.admin_mcp_create_token($1::text, 30) as made",
      [name],
    );
    return rows[0].made as { id: string; token: string };
  });
}

const refusal = async (run: () => Promise<unknown>) => {
  try {
    await run();
  } catch (error) {
    return describeFailure(error);
  }
  return "(no refusal)";
};

Deno.test({
  name: "smoke: every tool against a real database",
  ignore: !URL_ENV,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn(t) {
    const sql = await freshDatabase();
    const ownerKey = await createKey(sql, OWNER, "Smoke");
    const supportKey = await createKey(sql, SUPPORT, "Support laptop");
    let owner!: Caller;
    let support!: Caller;
    // In place of the Auth admin API: a profile row, which is what the
    // platform's signup trigger leaves behind for a new login.
    const madeLogins: string[] = [];
    const removedLogins: string[] = [];
    const accounts: Accounts = {
      async createLogin({ email, fullName, phone }) {
        const [taken] = await sql`select 1 from profiles where full_name = ${email}`;
        if (taken) throw new ToolError("USER_ALREADY_EXISTS");
        const id = crypto.randomUUID();
        await sql`
          insert into profiles (id, full_name, phone, role)
          values (${id}, ${fullName}, ${phone}, 'vendor')`;
        madeLogins.push(id);
        return id;
      },
      async deleteLogin(userId) {
        await sql`delete from profiles where id = ${userId}`;
        removedLogins.push(userId);
      },
    };
    const run = (name: string, args: unknown = {}, who = owner) =>
      callAs(sql, who, name, args, accounts) as Promise<any>;

    await t.step("a key identifies its admin; a wrong one identifies nobody", async () => {
      owner = (await authenticate(sql, `Bearer ${ownerKey.token}`))!;
      support = (await authenticate(sql, `Bearer ${supportKey.token}`))!;
      assertEquals(owner.adminId, OWNER);
      assertEquals(owner.tokenName, "Smoke");
      assertEquals(support.adminId, SUPPORT);
      assertEquals(await authenticate(sql, null), null);
      assertEquals(await authenticate(sql, "Bearer nonsense"), null);
      assertEquals(
        await authenticate(sql, `Bearer kin_mcp_${"0".repeat(64)}`),
        null,
      );
      const [{ last_used_at }] = await sql`
        select last_used_at from admin_mcp_tokens where id = ${ownerKey.id}`;
      assert(last_used_at !== null);
    });

    await t.step("the key is stored as a hash only, which clients cannot read", async () => {
      const [row] = await sql`select * from admin_mcp_tokens where id = ${ownerKey.id}`;
      assert(!JSON.stringify(row).includes(ownerKey.token));
      assertEquals(row.token_hash.length, 64);
      const said = await refusal(() =>
        sql.begin(async (tx) => {
          await tx.unsafe("select set_config('request.jwt.claims', $1::text, true)", [
            JSON.stringify({ sub: OWNER, role: "authenticated" }),
          ]);
          await tx.unsafe("set local role authenticated");
          await tx.unsafe("select token_hash from public.admin_mcp_tokens");
        })
      );
      assertEquals(said, "FORBIDDEN");
    });

    const reads: Record<string, unknown> = {
      whoami: {},
      dashboard_summary: {},
      search_orders: { query: "KIN", status: "pending", needs_attention: true, vendor_id: ACTIVE_STORE, from: "2020-01-01T00:00:00Z", limit: 10 },
      get_order: { order_number: "KIN-1001" },
      list_stores: { query: "kitchen", status: "active", category_id: CATEGORY },
      get_store: { vendor_id: ACTIVE_STORE },
      list_drivers: { query: "driver", status: "active", online: false },
      get_driver: { driver_id: ACTIVE_DRIVER },
      pending_approvals: {},
      list_complaints: { status: "pending" },
      get_complaint: { report_id: COMPLAINT },
      list_support_threads: { status: "all" },
      get_support_thread: { thread_id: THREAD, limit: 10 },
      platform_report: { from: "2020-01-01T00:00:00Z", to: "2030-01-01T00:00:00Z" },
      finance_overview: {},
      store_sales_report: {},
      driver_payout_report: {},
      store_balances: {},
      driver_balances: {},
      list_coupons: { active: true, vendor_id: ACTIVE_STORE },
      list_ads: { active: true, placement: "home_carousel" },
      list_notification_campaigns: { status: "draft" },
      list_price_campaigns: {},
      list_categories: {},
      list_service_areas: {},
      search_users: { query: "mona" },
      list_admin_log: { via_claude: true },
    };

    await t.step("every read-only tool has a case here", () => {
      assertEquals(
        tools.filter((tool) => tool.readOnly).map((tool) => tool.name).sort(),
        Object.keys(reads).sort(),
      );
    });

    for (const [name, args] of Object.entries(reads)) {
      await t.step(`${name} runs`, async () => {
        const result = await run(name, args);
        assert(result !== null && result !== undefined, "nothing came back");
      });
    }

    await t.step("whoami: the owner has everything, support has its one permission", async () => {
      assertEquals((await run("whoami")).permissions, ["*"]);
      const limited = await run("whoami", {}, support);
      assertEquals(limited.permissions, ["support.handle"]);
      assertEquals(limited.key_name, "Support laptop");
    });

    await t.step("get_order: money as numbers, people by name, no handover codes", async () => {
      const order = await run("get_order", { order_id: ORDER });
      assertEquals(order.total, 135.5);
      assertEquals(order.customer.full_name, "Mona Customer");
      assertEquals(order.items.length, 1);
      assertEquals(order.status_history[0].status, "pending");
      assertEquals(order.delivery_otp, undefined);
      assertEquals(order.pickup_code, undefined);
    });

    await t.step("search_orders finds the order that needs attention", async () => {
      const found = await run("search_orders", { needs_attention: true });
      assertEquals(found.map((o: any) => o.order_number), ["KIN-1001"]);
      assertEquals(await run("search_orders", { query: "100%" }), []);
    });

    await t.step("pending_approvals lists both queues", async () => {
      const waiting = await run("pending_approvals");
      assertEquals(waiting.stores.map((s: any) => s.id), [PENDING_STORE]);
      assertEquals(waiting.drivers.map((d: any) => d.id), [PENDING_DRIVER]);
    });

    await t.step("an admin without the permission is refused, and nothing changes", async () => {
      for (const [name, args] of [
        ["approve_store", { vendor_id: PENDING_STORE }],
        ["search_orders", {}],
        ["create_coupon", { code: "NOPE", discount_type: "fixed", value: 5 }],
        ["store_balances", {}],
      ] as const) {
        const error = await assertRejects(() => run(name, args, support), ToolError);
        assertEquals(error.code, "FORBIDDEN");
      }
      const [{ approval_status }] = await sql`
        select approval_status from vendors where id = ${PENDING_STORE}`;
      assertEquals(approval_status, "pending");
      // …while what its role does cover works.
      assertEquals((await run("list_complaints", {}, support)).length, 1);
    });

    await t.step("approve_store, and the log says Claude did it", async () => {
      const store = await run("approve_store", { vendor_id: PENDING_STORE });
      assertEquals(store.approval_status, "active");
      const [entry] = await sql`
        select actor_id, detail from admin_audit_log
        where action = 'vendor.status' and target_id = ${PENDING_STORE}`;
      assertEquals(entry.actor_id, OWNER);
      assertEquals(entry.detail.via, "claude");
      assertEquals(entry.detail.mcp_token_id, ownerKey.id);
      assertEquals(entry.detail.status, "active");
    });

    await t.step("an approved store cannot be suspended from here", async () => {
      const error = await assertRejects(
        () => run("reject_store", { vendor_id: ACTIVE_STORE }),
        ToolError,
      );
      assertEquals(error.code, "ONLY_PENDING");
    });

    await t.step("reject_driver keeps the reason; approve_driver refuses a second approval", async () => {
      const driver = await run("reject_driver", {
        driver_id: PENDING_DRIVER,
        reason: "Licence expired",
      });
      assertEquals(driver.approval_status, "suspended");
      assertEquals(driver.rejection_reason, "Licence expired");
      const error = await assertRejects(
        () => run("approve_driver", { driver_id: ACTIVE_DRIVER }),
        ToolError,
      );
      assertEquals(error.code, "ALREADY_ACTIVE");
    });

    await t.step("reject_store on a pending store", async () => {
      await sql`update vendors set approval_status = 'pending' where id = ${PENDING_STORE}`;
      const store = await run("reject_store", { vendor_id: PENDING_STORE });
      assertEquals(store.approval_status, "suspended");
    });

    await t.step("approve_driver on a pending driver", async () => {
      await sql`update drivers set approval_status = 'pending' where id = ${PENDING_DRIVER}`;
      const driver = await run("approve_driver", { driver_id: PENDING_DRIVER });
      assertEquals(driver.approval_status, "active");
    });

    const newStore = {
      owner_email: "hassan@example.com",
      owner_password: "correct-horse-battery",
      owner_full_name: "Hassan Ali",
      owner_phone: "0111",
      name: "Koshary El Tahrir",
      category_id: CATEGORY,
      address_text: "12 Tahrir St, Cairo",
      lat: 30.0444,
      lng: 31.2357,
      delivery_fee: 15,
    };

    await t.step("create_store: the owner's login, and a store that is live and theirs", async () => {
      const made = await run("create_store", newStore);
      assertEquals(made.approval_status, "active");
      assertEquals(made.is_open, true);
      assertEquals(made.owner_id, madeLogins.at(-1));

      const store = await run("get_store", { vendor_id: made.vendor_id });
      assertEquals(store.name, "Koshary El Tahrir");
      assertEquals(store.owner.full_name, "Hassan Ali");
      assertEquals(store.phone, "0111");
      assertEquals(store.delivery_fee, 15);
      assertEquals(store.commission_rate, 10);
      assertEquals(store.lat, 30.0444);

      const [entry] = await sql`
        select actor_id, detail from admin_audit_log
        where action = 'vendor.create_account' and target_id = ${made.vendor_id}`;
      assertEquals(entry.actor_id, OWNER);
      assertEquals(entry.detail.via, "claude");
      assertEquals(entry.detail.email, "hassan@example.com");
      assert(!JSON.stringify(entry).includes("correct-horse-battery"));
    });

    await t.step("create_store: held for review when asked", async () => {
      const made = await run("create_store", { ...newStore, name: "Later Kitchen", approve: false });
      assertEquals(made.approval_status, "pending");
      assertEquals(made.is_open, false);
    });

    await t.step("create_store: refused without the permission, and nobody gets a login", async () => {
      const before = madeLogins.length;
      const error = await assertRejects(() => run("create_store", newStore, support), ToolError);
      assertEquals(error.code, "FORBIDDEN");
      assertEquals(madeLogins.length, before);
    });

    await t.step("create_store: a store the database refuses takes its login with it", async () => {
      const [{ count: before }] = await sql`select count(*) from profiles`;
      // Something the tool's own checks let through and the table does not.
      await sql`alter table vendors add constraint smoke_no_zamalek check (name <> 'Zamalek Grill')`;
      const said = await refusal(() =>
        run("create_store", { ...newStore, name: "Zamalek Grill" })
      );
      await sql`alter table vendors drop constraint smoke_no_zamalek`;
      assert(said.startsWith("INVALID_VALUE"), said);
      assertEquals(removedLogins, [madeLogins.at(-1)]);
      const [{ count: after }] = await sql`select count(*) from profiles`;
      assertEquals(after, before);
      const [{ count: stores }] = await sql`select count(*) from vendors where name = 'Zamalek Grill'`;
      assertEquals(Number(stores), 0);
    });

    await t.step("complaints: reply and resolve, by the support admin", async () => {
      const sent = await run("reply_to_complaint", {
        report_id: COMPLAINT,
        message: "Sorry about that — a refund is on its way.",
        resolve: true,
      }, support);
      assert(sent.sent);
      const complaint = await run("get_complaint", { report_id: COMPLAINT }, support);
      assertEquals(complaint.status, "resolved");
      assertEquals(complaint.messages.at(-1).is_from_admin, true);
      assertEquals(await run("list_complaints", {}, support), []);
    });

    await t.step("support chat: reply, then resolve", async () => {
      await run("reply_to_support_thread", { thread_id: THREAD, message: "On its way." }, support);
      const thread = await run("get_support_thread", { thread_id: THREAD }, support);
      assertEquals(thread.messages.length, 2);
      assertEquals(thread.last_message.is_from_admin, true);
      const [message] = await sql`
        select sender_id from support_messages where is_from_admin`;
      assertEquals(message.sender_id, SUPPORT);

      const done = await run("set_support_thread_status", { thread_id: THREAD, status: "resolved" }, support);
      assertEquals(done.status, "resolved");
    });

    await t.step("coupons: create, then change", async () => {
      const coupon = await run("create_coupon", {
        code: "welcome20",
        discount_type: "percentage",
        value: 20,
        max_discount: 50,
        expires_at: "2030-01-01T00:00:00Z",
        first_order_only: true,
      });
      assertEquals(coupon.code, "WELCOME20");
      assertEquals(coupon.value, 20);
      assertEquals(coupon.per_user_limit, 1);
      assertEquals(coupon.funded_by, "platform");

      const changed = await run("update_coupon", {
        coupon_id: coupon.id,
        is_active: false,
        expires_at: null,
        per_user_limit: 3,
      });
      assertEquals(changed.is_active, false);
      assertEquals(changed.expires_at, null);
      assertEquals(changed.per_user_limit, 3);

      // The same code twice is the database's refusal, put into words.
      const said = await refusal(() =>
        run("create_coupon", { code: "WELCOME20", discount_type: "fixed", value: 5 })
      );
      assert(said.startsWith("ALREADY_EXISTS"), said);
    });

    await t.step("a write that fails leaves nothing behind", async () => {
      const [{ count: before }] = await sql`select count(*) from admin_audit_log`;
      const said = await refusal(() =>
        run("update_service_area", { area_id: AREA, radius_km: 250, name: null })
      );
      assert(said !== "(no refusal)", "a null name should have been refused");
      const [{ radius_km }] = await sql`select radius_km from service_areas where id = ${AREA}`;
      assertEquals(Number(radius_km), 20);
      const [{ count: after }] = await sql`select count(*) from admin_audit_log`;
      assertEquals(after, before);
    });

    await t.step("ads, categories and service areas: create, then change", async () => {
      const ad = await run("create_ad", {
        image_url: "https://example.com/eid.png",
        title: "Eid",
        banner_type: "vendor",
        vendor_id: ACTIVE_STORE,
        placement: "home_inline",
        starts_at: "2026-10-05T00:00:00Z",
        is_active: false,
      });
      assertEquals(ad.placement, "home_inline");
      assertEquals((await run("update_ad", { ad_id: ad.id, is_active: true, title: null })).is_active, true);

      const category = await run("create_category", { name: "Bakeries", name_ar: "مخابز", parent_id: CATEGORY });
      assertEquals(category.name_ar, "مخابز");
      assertEquals((await run("update_category", { category_id: category.id, sort_order: 4 })).sort_order, 4);

      const area = await run("create_service_area", { name: "Giza", lat: 30.01, lng: 31.21, radius_km: 7.5 });
      assertEquals(area.radius_km, 7.5);
      assertEquals((await run("update_service_area", { area_id: AREA, is_active: false })).is_active, false);
    });

    await t.step("every write through Claude is in the log, under the right admin", async () => {
      const log = await run("list_admin_log", { via_claude: true, limit: 100 });
      const actions = new Set(log.map((entry: any) => entry.action));
      for (const action of [
        "vendor.status", "vendor.create_account", "driver.status", "report.reply", "support.reply",
        "support.status", "coupon.create", "coupon.update", "ad.create",
        "ad.update", "category.create", "category.update",
        "service_area.create", "service_area.update",
      ]) {
        assert(actions.has(action), `${action} was not logged`);
      }
      const reply = log.find((entry: any) => entry.action === "support.reply");
      assertEquals(reply.actor_name, "Support Admin");
      // Making the keys was logged too, but that was not Claude.
      const [{ count }] = await sql`
        select count(*) from admin_audit_log
        where action = 'mcp_token.create' and not detail ? 'via'`;
      assertEquals(Number(count), 2);
    });

    await t.step("a read-only tool cannot write, whatever it is asked", async () => {
      const said = await refusal(() =>
        sql.begin(async (tx) => {
          await tx.unsafe("set local role authenticated");
          await tx.unsafe("set local transaction_read_only = on");
          await tx.unsafe("update public.service_areas set name = 'x'");
        })
      );
      assertEquals(said, "READ_ONLY");
    });

    await t.step("a key cannot be used to make another key", async () => {
      const said = await refusal(() =>
        sql.begin(async (tx) => {
          await tx.unsafe("select set_config('request.jwt.claims', $1::text, true)", [
            JSON.stringify({ sub: OWNER, role: "authenticated", via: "mcp", mcp_token_id: ownerKey.id }),
          ]);
          await tx.unsafe("set local role authenticated");
          await tx.unsafe("select public.admin_mcp_create_token('Second', 30)");
        })
      );
      assertEquals(said, "FORBIDDEN");
    });

    await t.step("a key stops with its owner: blocked, then revoked", async () => {
      await sql`update profiles set is_blocked = true where id = ${SUPPORT}`;
      assertEquals(await authenticate(sql, `Bearer ${supportKey.token}`), null);
      await sql`update profiles set is_blocked = false where id = ${SUPPORT}`;
      assert(await authenticate(sql, `Bearer ${supportKey.token}`));

      // The support admin cannot revoke somebody else's key…
      const asAdmin = (adminId: string, statement: string, params: string[]) =>
        sql.begin(async (tx) => {
          await tx.unsafe("select set_config('request.jwt.claims', $1::text, true)", [
            JSON.stringify({ sub: adminId, role: "authenticated" }),
          ]);
          await tx.unsafe("set local role authenticated");
          return await tx.unsafe(statement, params);
        });
      assertEquals(
        await refusal(() => asAdmin(SUPPORT, "select public.admin_mcp_revoke_token($1::uuid)", [ownerKey.id])),
        "FORBIDDEN",
      );
      // …and sees only their own, while the owner sees both.
      assertEquals((await asAdmin(SUPPORT, "select id from public.admin_mcp_tokens", [])).length, 1);
      assertEquals((await asAdmin(OWNER, "select id from public.admin_mcp_tokens", [])).length, 2);

      await asAdmin(OWNER, "select public.admin_mcp_revoke_token($1::uuid)", [supportKey.id]);
      assertEquals(await authenticate(sql, `Bearer ${supportKey.token}`), null);
      assert(await authenticate(sql, `Bearer ${ownerKey.token}`));
    });

    await t.step("an expired key is no key", async () => {
      await sql`update admin_mcp_tokens set expires_at = now() - interval '1 second' where id = ${ownerKey.id}`;
      assertEquals(await authenticate(sql, `Bearer ${ownerKey.token}`), null);
    });

    await sql.end();
  },
});
