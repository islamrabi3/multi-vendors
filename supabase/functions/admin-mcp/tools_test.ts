// Run with: deno test supabase/functions/admin-mcp/
//
// These run against a stand-in database that records what it was asked, so
// they check what each tool asks for and in what order. That the SQL itself
// runs is checked against a real Postgres by smoke_test.ts.
import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert@1";

import { validate } from "./schema.ts";
import {
  type Accounts,
  type Caller,
  type Db,
  describeTools,
  runTool as runToolWith,
  ToolError,
  tools,
} from "./tools.ts";

const ID = "11111111-2222-4333-8444-555555555555";

const caller: Caller = {
  adminId: ID,
  adminName: "Test Admin",
  tokenId: ID,
  tokenName: "Laptop",
};

const OWNER_ID = "99999999-8888-4777-8666-555555555555";

/// Stands in for the Auth admin API, and remembers what it was asked.
const logins = {
  created: [] as Parameters<Accounts["createLogin"]>[0][],
  deleted: [] as string[],
  reset() {
    this.created = [];
    this.deleted = [];
  },
};

const accounts: Accounts = {
  createLogin(input) {
    logins.created.push(input);
    return Promise.resolve(OWNER_ID);
  },
  deleteLogin(userId) {
    logins.deleted.push(userId);
    return Promise.resolve();
  },
};

const runTool = (db: Db, who: Caller, name: string, args: unknown) =>
  runToolWith(db, who, name, args, accounts);

interface Call {
  text: string;
  params: unknown[];
}

const isPermissionCheck = (text: string) =>
  text.includes("public.has_permission(k)") || text === "select public.is_admin()";

/// Answers the permission check with [allowed], and everything else with
/// whatever [answer] returns (a plausible row by default).
function fakeDb(
  { allowed = true, answer }: {
    allowed?: boolean;
    answer?: (call: Call) => unknown;
  } = {},
) {
  const calls: Call[] = [];
  const db: Db = {
    json<T>(text: string, params: unknown[] = []) {
      const call = { text, params };
      calls.push(call);
      if (isPermissionCheck(text)) return Promise.resolve(allowed as T);
      const custom = answer?.(call);
      if (custom !== undefined) return Promise.resolve(custom as T);
      if (text.includes("select approval_status")) {
        return Promise.resolve("pending" as T);
      }
      return Promise.resolve({ id: ID, code: "X", status: "open" } as T);
    },
  };
  return { db, calls, work: () => calls.filter((c) => !isPermissionCheck(c.text)) };
}

/// The least each tool will accept.
const sample: Record<string, Record<string, unknown>> = {
  whoami: {},
  dashboard_summary: {},
  search_orders: {},
  get_order: { order_id: ID },
  list_stores: {},
  get_store: { vendor_id: ID },
  approve_store: { vendor_id: ID },
  reject_store: { vendor_id: ID },
  create_store: {
    owner_email: "owner@example.com",
    owner_password: "correct-horse-battery",
    owner_full_name: "Hassan Ali",
    name: "Koshary El Tahrir",
    category_id: ID,
    address_text: "12 Tahrir St, Cairo",
    lat: 30.04,
    lng: 31.23,
  },
  list_drivers: {},
  get_driver: { driver_id: ID },
  approve_driver: { driver_id: ID },
  reject_driver: { driver_id: ID, reason: "Licence photo unreadable" },
  pending_approvals: {},
  list_complaints: {},
  get_complaint: { report_id: ID },
  reply_to_complaint: { report_id: ID, message: "We are on it." },
  list_support_threads: {},
  get_support_thread: { thread_id: ID },
  reply_to_support_thread: { thread_id: ID, message: "Hello" },
  set_support_thread_status: { thread_id: ID, status: "resolved" },
  platform_report: {},
  finance_overview: {},
  store_sales_report: {},
  driver_payout_report: {},
  store_balances: {},
  driver_balances: {},
  list_coupons: {},
  create_coupon: { code: "save10", discount_type: "percentage", value: 10 },
  update_coupon: { coupon_id: ID, is_active: false },
  list_ads: {},
  create_ad: { image_url: "https://example.com/a.png" },
  update_ad: { ad_id: ID, is_active: false },
  list_notification_campaigns: {},
  list_price_campaigns: {},
  list_categories: {},
  create_category: { name: "Bakeries" },
  update_category: { category_id: ID, is_active: false },
  list_service_areas: {},
  create_service_area: { name: "Downtown", lat: 30.04, lng: 31.23, radius_km: 5 },
  update_service_area: { area_id: ID, radius_km: 8 },
  search_users: { query: "ahmed" },
  list_admin_log: {},
};

/// The highest `$n` a statement mentions.
function placeholders(text: string): number {
  const found = [...text.matchAll(/\$(\d+)/g)].map((m) => Number(m[1]));
  return found.length ? Math.max(...found) : 0;
}

const WRITES = /\b(insert into|update public\.|delete from)\b|admin_set_|report_send_message/i;

Deno.test("every tool has a sample, and every sample a tool", () => {
  assertEquals(
    tools.map((t) => t.name).sort(),
    Object.keys(sample).sort(),
  );
});

Deno.test("tool names are unique and described", () => {
  const names = new Set(tools.map((t) => t.name));
  assertEquals(names.size, tools.length);
  for (const tool of describeTools()) {
    assert(tool.description.length > 20, `${tool.name} needs a description`);
    assertEquals(tool.inputSchema.type, "object");
    assertEquals(tool.inputSchema.additionalProperties, false);
  }
});

for (const tool of tools) {
  const args = sample[tool.name] ?? {};

  Deno.test(`${tool.name}: its sample passes its own schema`, () => {
    assertEquals(validate(tool.input, args), []);
  });

  Deno.test(`${tool.name}: asks for permission before anything else`, async () => {
    const { db, calls } = fakeDb();
    await runTool(db, caller, tool.name, args);
    assert(isPermissionCheck(calls[0].text));
    if (tool.permission) {
      assertEquals(calls[0].params, [`{${tool.permission.join(",")}}`]);
    }
  });

  Deno.test(`${tool.name}: does nothing when the admin lacks the permission`, async () => {
    const { db, work } = fakeDb({ allowed: false });
    const error = await assertRejects(
      () => runTool(db, caller, tool.name, args),
      ToolError,
    );
    assertEquals(error.code, "FORBIDDEN");
    assertEquals(work(), []);
  });

  Deno.test(`${tool.name}: every placeholder has a value`, async () => {
    const { db, work } = fakeDb();
    await runTool(db, caller, tool.name, args);
    assert(work().length > 0, "the tool ran no query");
    for (const call of work()) {
      assertEquals(placeholders(call.text), call.params.length, call.text);
      // Each value is cast, so the driver never has to guess a type.
      for (const match of call.text.matchAll(/\$\d+(?!\d|::)/g)) {
        throw new Error(`uncast ${match[0]} in: ${call.text}`);
      }
    }
  });

  Deno.test(`${tool.name}: rejects an argument it does not know`, async () => {
    const { db, calls } = fakeDb();
    const error = await assertRejects(
      () => runTool(db, caller, tool.name, { ...args, drop_table: true }),
      ToolError,
    );
    assertEquals(error.code, "INVALID_ARGUMENTS");
    assertEquals(calls, []);
  });

  if (tool.readOnly) {
    Deno.test(`${tool.name}: read-only, so it writes nothing`, async () => {
      const { db, work } = fakeDb();
      await runTool(db, caller, tool.name, args);
      for (const call of work()) {
        assert(!WRITES.test(call.text), `writes: ${call.text}`);
        assert(!call.text.includes("admin_mcp_log"));
      }
    });
  } else {
    Deno.test(`${tool.name}: a write, so it leaves a record`, async () => {
      const { db, work } = fakeDb();
      await runTool(db, caller, tool.name, args);
      const texts = work().map((c) => c.text).join("\n");
      // The status RPCs log themselves; everything else goes through
      // admin_mcp_log.
      assert(
        texts.includes("admin_mcp_log") || /admin_set_(vendor|driver)_status/.test(texts),
        "no audit entry",
      );
    });
  }
}

Deno.test("an unknown tool is refused", async () => {
  const { db, calls } = fakeDb();
  const error = await assertRejects(
    () => runTool(db, caller, "drop_everything", {}),
    ToolError,
  );
  assertEquals(error.code, "UNKNOWN_TOOL");
  assertEquals(calls, []);
});

Deno.test("a badly shaped id never reaches the database", async () => {
  const { db, calls } = fakeDb();
  await assertRejects(
    () => runTool(db, caller, "get_store", { vendor_id: "1; drop table vendors" }),
    ToolError,
  );
  assertEquals(calls, []);
});

Deno.test("search_orders: each filter becomes a bound condition", async () => {
  const { db, work } = fakeDb();
  await runTool(db, caller, "search_orders", {
    query: "100%_off",
    status: "pending",
    vendor_id: ID,
    from: "2026-10-01T00:00:00Z",
    needs_attention: true,
    limit: 5,
  });
  const [call] = work();
  assertStringIncludes(call.text, "o.status = $2::public.order_status");
  assertStringIncludes(call.text, "o.vendor_id = $3::uuid");
  assertStringIncludes(call.text, "o.created_at >= $4::timestamptz");
  assertStringIncludes(call.text, "interval '30 minutes'");
  // The wildcards somebody typed are searched for, not obeyed.
  assertEquals(call.params, [
    "%100\\%\\_off%",
    "pending",
    ID,
    "2026-10-01T00:00:00Z",
    5,
    0,
  ]);
});

Deno.test("search_orders: limit is capped by the schema", async () => {
  const { db } = fakeDb();
  const error = await assertRejects(
    () => runTool(db, caller, "search_orders", { limit: 5000 }),
    ToolError,
  );
  assertStringIncludes(error.message, "at most 100");
});

Deno.test("get_order: needs an id or a number, and hides the handover codes", async () => {
  const none = fakeDb();
  await assertRejects(() => runTool(none.db, caller, "get_order", {}), ToolError);

  const { db, work } = fakeDb();
  await runTool(db, caller, "get_order", { order_number: "KIN-1042" });
  const [call] = work();
  assertStringIncludes(call.text, "- 'delivery_otp' - 'pickup_code'");
  assertStringIncludes(call.text, "o.order_number = $1::text");
  assertEquals(call.params, ["KIN-1042"]);
});

Deno.test("get_order: says so when there is no such order", async () => {
  const { db } = fakeDb({ answer: () => null });
  const error = await assertRejects(
    () => runTool(db, caller, "get_order", { order_id: ID }),
    ToolError,
  );
  assertEquals(error.code, "NOT_FOUND");
});

Deno.test("approve_store: sets the store active through the RPC", async () => {
  const { db, work } = fakeDb();
  await runTool(db, caller, "approve_store", { vendor_id: ID });
  const rpc = work().find((c) => c.text.includes("admin_set_vendor_status"))!;
  assertEquals(rpc.params, [ID, "active"]);
});

Deno.test("reject_store: only a pending applicant can be turned down", async () => {
  const { db, work } = fakeDb({
    answer: (c) => c.text.includes("select approval_status") ? "active" : undefined,
  });
  const error = await assertRejects(
    () => runTool(db, caller, "reject_store", { vendor_id: ID }),
    ToolError,
  );
  assertEquals(error.code, "ONLY_PENDING");
  assert(!work().some((c) => c.text.includes("admin_set_vendor_status")));
});

Deno.test("approve_driver: an approved driver is not approved twice", async () => {
  const { db, work } = fakeDb({
    answer: (c) => c.text.includes("select approval_status") ? "active" : undefined,
  });
  const error = await assertRejects(
    () => runTool(db, caller, "approve_driver", { driver_id: ID }),
    ToolError,
  );
  assertEquals(error.code, "ALREADY_ACTIVE");
  assert(!work().some((c) => c.text.includes("admin_set_driver_status")));
});

Deno.test("reject_driver: needs a reason, and passes it on", async () => {
  const missing = fakeDb();
  await assertRejects(
    () => runTool(missing.db, caller, "reject_driver", { driver_id: ID }),
    ToolError,
  );

  const { db, work } = fakeDb();
  await runTool(db, caller, "reject_driver", { driver_id: ID, reason: "No licence" });
  const rpc = work().find((c) => c.text.includes("admin_set_driver_status"))!;
  assertEquals(rpc.params, [ID, "suspended", "No licence"]);
});

Deno.test("reject of somebody who does not exist is NOT_FOUND", async () => {
  const { db } = fakeDb({ answer: () => null });
  const error = await assertRejects(
    () => runTool(db, caller, "reject_store", { vendor_id: ID }),
    ToolError,
  );
  assertEquals(error.code, "NOT_FOUND");
});

const store = sample.create_store;

/// The row an insert was given, by column name.
function inserted(call: Call, table: string): Record<string, unknown> {
  const columns = call.text.match(new RegExp(`${table} \\(([^)]+)\\) values`))![1].split(", ");
  return Object.fromEntries(columns.map((c, i) => [c, call.params[i]]));
}

Deno.test("create_store: a login for the owner, then an open, approved store that is theirs", async () => {
  logins.reset();
  const { db, work } = fakeDb({
    answer: (c) =>
      c.text.includes("insert into public.vendors")
        ? { id: ID, approval_status: "active", is_open: true }
        : undefined,
  });
  const result: any = await runTool(db, caller, "create_store", {
    ...store,
    owner_email: "  Owner@Example.com ",
    owner_phone: "0100",
  });

  assertEquals(logins.created, [{
    email: "owner@example.com",
    password: "correct-horse-battery",
    fullName: "Hassan Ali",
    phone: "0100",
    username: null,
    role: "vendor",
  }]);
  const row = inserted(work().find((c) => c.text.includes("insert into public.vendors"))!, "vendors");
  assertEquals(row.owner_id, OWNER_ID);
  assertEquals(row.approval_status, "active");
  assertEquals(row.is_open, true);
  // The store's phone falls back to the owner's, as on the dashboard.
  assertEquals(row.phone, "0100");
  assertEquals(row.commission_rate, 10);
  assertEquals(row.subscription_fee, 0);
  assertEquals(logins.deleted, []);
  assertEquals(result.vendor_id, ID);
  assertEquals(result.owner_id, OWNER_ID);
  // The password went to the Auth API and nowhere else.
  assert(!JSON.stringify(result).includes("correct-horse-battery"));
  assert(!work().some((c) => JSON.stringify(c.params).includes("correct-horse-battery")));
});

Deno.test("create_store: approve false leaves it pending and shut", async () => {
  logins.reset();
  const { db, work } = fakeDb();
  await runTool(db, caller, "create_store", { ...store, approve: false });
  const row = inserted(work().find((c) => c.text.includes("insert into public.vendors"))!, "vendors");
  assertEquals(row.approval_status, "pending");
  assertEquals(row.is_open, false);
});

Deno.test("create_store: a subscription store pays no commission", async () => {
  logins.reset();
  const { db, work } = fakeDb();
  await runTool(db, caller, "create_store", {
    ...store,
    billing_model: "subscription",
    subscription_fee: 500,
    commission_rate: 15,
  });
  const row = inserted(work().find((c) => c.text.includes("insert into public.vendors"))!, "vendors");
  assertEquals(row.commission_rate, 0);
  assertEquals(row.subscription_fee, 500);
});

Deno.test("create_store: no login is made for an admin who may not, or for bad details", async () => {
  logins.reset();
  const denied = fakeDb({ allowed: false });
  await assertRejects(() => runTool(denied.db, caller, "create_store", store), ToolError);

  const cases: [Record<string, unknown>, string][] = [
    [{ ...store, owner_email: "not-an-email" }, "INVALID_EMAIL"],
    [{ ...store, owner_username: "a b" }, "INVALID_USERNAME"],
    [{ ...store, owner_password: "short" }, "INVALID_ARGUMENTS"],
    [{ ...store, lat: 200 }, "INVALID_ARGUMENTS"],
  ];
  for (const [args, code] of cases) {
    const { db } = fakeDb();
    const error = await assertRejects(() => runTool(db, caller, "create_store", args), ToolError);
    assertEquals(error.code, code);
  }

  // A category that does not exist is caught before anybody gets an account.
  const noCategory = fakeDb({
    answer: (c) => c.text.includes("from public.vendor_categories") ? null : undefined,
  });
  const error = await assertRejects(
    () => runTool(noCategory.db, caller, "create_store", store),
    ToolError,
  );
  assertEquals(error.code, "NOT_FOUND");

  assertEquals(logins.created, []);
});

Deno.test("create_store: if the store cannot be written, the login is removed again", async () => {
  logins.reset();
  const db: Db = {
    json<T>(text: string) {
      if (text.includes("insert into public.vendors")) {
        return Promise.reject({ code: "23514", constraint_name: "vendors_billing_model_check" });
      }
      return Promise.resolve((isPermissionCheck(text) ? true : { id: ID }) as T);
    },
  };
  await assertRejects(() => runTool(db, caller, "create_store", store));
  assertEquals(logins.created.length, 1);
  assertEquals(logins.deleted, [OWNER_ID]);
});

Deno.test("create_store: without the Auth API to hand, it refuses rather than half-doing it", async () => {
  const { db, work } = fakeDb();
  const error = await assertRejects(
    () => runToolWith(db, caller, "create_store", store),
    ToolError,
  );
  assertEquals(error.code, "UNAVAILABLE");
  assertEquals(work(), []);
});

Deno.test("reply_to_complaint: sends through report_send_message", async () => {
  const { db, work } = fakeDb({
    answer: (c) => c.text.includes("report_send_message") ? ID : undefined,
  });
  const result = await runTool(db, caller, "reply_to_complaint", {
    report_id: ID,
    message: "Refund is on its way.",
    resolve: true,
  });
  const rpc = work().find((c) => c.text.includes("report_send_message"))!;
  assertEquals(rpc.params, [ID, "Refund is on its way.", true]);
  assertEquals(result, { sent: true, message_id: ID, resolved: true });
});

Deno.test("reply_to_complaint: nothing to say and nothing to resolve is refused", async () => {
  const { db, work } = fakeDb();
  await assertRejects(
    () => runTool(db, caller, "reply_to_complaint", { report_id: ID }),
    ToolError,
  );
  assertEquals(work(), []);
});

Deno.test("reply_to_support_thread: writes as the admin, never as a given sender", async () => {
  const { db, work } = fakeDb();
  await runTool(db, caller, "reply_to_support_thread", {
    thread_id: ID,
    message: "  Hello  ",
  });
  const insert = work().find((c) => c.text.includes("insert into public.support_messages"))!;
  assertStringIncludes(insert.text, "auth.uid(), true");
  assertEquals(insert.params, [ID, "Hello"]);
});

Deno.test("reply_to_support_thread: no such chat, no message", async () => {
  const { db, work } = fakeDb({ answer: () => null });
  const error = await assertRejects(
    () => runTool(db, caller, "reply_to_support_thread", { thread_id: ID, message: "Hi" }),
    ToolError,
  );
  assertEquals(error.code, "NOT_FOUND");
  assert(!work().some((c) => c.text.includes("insert into")));
});

Deno.test("list_complaints: unresolved by default, everything on request", async () => {
  const open = fakeDb();
  await runTool(open.db, caller, "list_complaints", {});
  assertStringIncludes(open.work()[0].text, "r.status <> 'resolved'");

  const all = fakeDb();
  await runTool(all.db, caller, "list_complaints", { status: "all" });
  assert(!/r\.status (=|<>)/.test(all.work()[0].text));
});

Deno.test("reports: an open-ended period is passed as nulls", async () => {
  for (const name of ["platform_report", "finance_overview", "store_sales_report", "driver_payout_report"]) {
    const { db, work } = fakeDb();
    await runTool(db, caller, name, {});
    assertEquals(work()[0].params, [null, null]);
  }
});

Deno.test("reports: a date that is not a date is refused", async () => {
  const { db, calls } = fakeDb();
  await assertRejects(
    () => runTool(db, caller, "platform_report", { from: "last tuesday" }),
    ToolError,
  );
  assertEquals(calls, []);
});

Deno.test("create_coupon: capitals, dashboard defaults, platform-funded without a store", async () => {
  const { db, work } = fakeDb();
  await runTool(db, caller, "create_coupon", {
    code: " save10 ",
    discount_type: "percentage",
    value: 10,
    funded_by: "vendor",
  });
  const insert = work().find((c) => c.text.includes("insert into public.coupons"))!;
  const columns = insert.text.match(/coupons \(([^)]+)\) values/)![1].split(", ");
  const row = Object.fromEntries(columns.map((c, i) => [c, insert.params[i]]));
  assertEquals(row.code, "SAVE10");
  assertEquals(row.per_user_limit, 1);
  assertEquals(row.is_active, true);
  // Charging a store for a code that is not its own is not a thing.
  assertEquals(row.funded_by, "platform");
});

Deno.test("create_coupon: a percentage over 100 or a zero value is refused", async () => {
  for (const value of [0, 150]) {
    const { db, work } = fakeDb();
    await assertRejects(
      () => runTool(db, caller, "create_coupon", { code: "X", discount_type: "percentage", value }),
      ToolError,
    );
    assertEquals(work(), []);
  }
});

Deno.test("update_coupon: only the fields given, and null clears one", async () => {
  const { db, work } = fakeDb();
  await runTool(db, caller, "update_coupon", {
    coupon_id: ID,
    expires_at: null,
    is_active: false,
  });
  const update = work().find((c) => c.text.includes("update public.coupons"))!;
  assertStringIncludes(update.text, "set expires_at = $2::timestamptz, is_active = $3::boolean");
  assertEquals(update.params, [ID, null, false]);
});

Deno.test("update tools: nothing to change is refused before any write", async () => {
  const cases: [string, Record<string, unknown>][] = [
    ["update_coupon", { coupon_id: ID }],
    ["update_ad", { ad_id: ID }],
    ["update_category", { category_id: ID }],
    ["update_service_area", { area_id: ID }],
  ];
  for (const [name, args] of cases) {
    const { db, work } = fakeDb();
    const error = await assertRejects(() => runTool(db, caller, name, args), ToolError);
    assertEquals(error.code, "NOTHING_TO_UPDATE");
    assertEquals(work(), []);
  }
});

Deno.test("update tools: a row that is not there is NOT_FOUND, with no log line", async () => {
  const { db, work } = fakeDb({ answer: () => null });
  const error = await assertRejects(
    () => runTool(db, caller, "update_ad", { ad_id: ID, is_active: false }),
    ToolError,
  );
  assertEquals(error.code, "NOT_FOUND");
  assert(!work().some((c) => c.text.includes("admin_mcp_log")));
});

Deno.test("create_ad: only known placements", async () => {
  const { db, calls } = fakeDb();
  await assertRejects(
    () => runTool(db, caller, "create_ad", { image_url: "https://x/y.png", placement: "everywhere" }),
    ToolError,
  );
  assertEquals(calls, []);
});

Deno.test("create_service_area: the radius must be one the table accepts", async () => {
  const { db, calls } = fakeDb();
  await assertRejects(
    () => runTool(db, caller, "create_service_area", { name: "Everywhere", lat: 0, lng: 0, radius_km: 900 }),
    ToolError,
  );
  assertEquals(calls, []);
});

Deno.test("list_admin_log: can be narrowed to what Claude did", async () => {
  const { db, work } = fakeDb();
  await runTool(db, caller, "list_admin_log", { via_claude: true });
  assertStringIncludes(work()[0].text, "l.detail ->> 'via' = 'claude'");
});

Deno.test("whoami: needs no permission beyond being an admin", async () => {
  const { db, calls } = fakeDb();
  await runTool(db, caller, "whoami", {});
  assertEquals(calls[0].text, "select public.is_admin()");
  assertEquals(calls[1].params, ["Laptop"]);
});
