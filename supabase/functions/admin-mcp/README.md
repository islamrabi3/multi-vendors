# admin-mcp

An MCP server that lets Claude work the Kitchen IN admin console: look up
orders, stores and drivers, answer complaints and support chats, approve
applicants, read reports and balances, and keep coupons, ads, categories and
service areas up to date.

It is a Supabase Edge Function. Claude Code and Claude Desktop connect to it
over HTTP with a key an admin makes on the dashboard.

## How it decides what is allowed

A key stands in for the admin who made it. For each tool call the function:

1. Hashes the key and looks it up (`admin_mcp_authenticate`). Unknown,
   revoked or expired keys, and keys whose owner is blocked, deleted or no
   longer an admin, all get the same `401`.
2. Opens a transaction, switches it to the `authenticated` role and puts the
   admin's id in the request claims — what PostgREST does for a signed-in
   dashboard session.
3. Runs the tool. `auth.uid()`, `has_permission()` and every row policy answer
   as they would for that admin, so a key can do what its owner can and no
   more. Read-only tools run in a read-only transaction.

The service role is never used to run a tool, with one exception:
`create_store` makes the owner's login through the Auth admin API, which
nothing else can write to. It does so only after the admin's own permission
has been checked, the store row itself is still written as the admin, and the
login is removed again if the store cannot be created. Every write is recorded in
`admin_audit_log` under the admin's name with `detail.via = "claude"` and the
key's id.

## Connecting

Make a key on the dashboard: **System → Claude keys → New key**. It is shown
once, with the command below already filled in.

**Claude Code**

```sh
claude mcp add --transport http kitchen-in-admin \
  https://<project-ref>.supabase.co/functions/v1/admin-mcp \
  --header "Authorization: Bearer kin_mcp_…"
```

**Claude Desktop** — in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "kitchen-in-admin": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "https://<project-ref>.supabase.co/functions/v1/admin-mcp",
        "--header", "Authorization: Bearer kin_mcp_…"
      ]
    }
  }
}
```

A key is as good as the admin's password for everything listed below. Keep it
out of chats and shared files, give each device its own, and revoke one from
the same page the moment it is not needed. Keys expire (90 days unless chosen
otherwise) and an admin can hold at most 10 working keys.

## Tools

| Area | Tools | Permission |
| --- | --- | --- |
| Session | `whoami`, `dashboard_summary` | any admin |
| Orders | `search_orders`, `get_order` | `orders.view` |
| Stores | `list_stores`, `get_store` | `vendors.view` |
| | `approve_store`, `reject_store`, `create_store` | `vendors.approve` |
| Drivers | `list_drivers`, `get_driver` | `drivers.view` |
| | `approve_driver`, `reject_driver` | `drivers.approve` |
| Approvals | `pending_approvals` | `vendors.view` or `drivers.view` |
| Complaints | `list_complaints`, `get_complaint`, `reply_to_complaint` | `support.handle` |
| Support chat | `list_support_threads`, `get_support_thread`, `reply_to_support_thread`, `set_support_thread_status` | `support.handle` |
| Reports | `platform_report`, `finance_overview`, `store_sales_report`, `driver_payout_report`, `store_balances`, `driver_balances` | `reports.view` |
| Coupons | `list_coupons`, `create_coupon`, `update_coupon` | `promos.manage` |
| Ads | `list_ads`, `create_ad`, `update_ad` | `ads.manage` |
| Campaigns | `list_notification_campaigns` | `notifications.send` |
| | `list_price_campaigns` | `catalog.manage` |
| Categories | `list_categories` | `catalog.manage` or `vendors.view` |
| | `create_category`, `update_category` | `catalog.manage` |
| Service areas | `list_service_areas`, `create_service_area`, `update_service_area` | `content.manage` |
| People | `search_users` | `users.block` |
| Log | `list_admin_log` | `staff.manage` |

### Deliberately not here

Anything that moves money or takes a live account off the platform stays at
the dashboard: settlements, cash hand-overs, refunds, wallet and ledger
adjustments, price adjustments and price campaigns, the all-store delivery
fee, suspending an approved store or driver, blocking or deleting users,
cancelling orders and assigning drivers. So do creating driver accounts,
building or importing a store's menu, sending push announcements,
deleting anything, uploading images, and managing roles and keys.

`reject_store` and `reject_driver` work only on applicants still pending.

## Development

```sh
cd supabase/functions/admin-mcp

# What each tool asks the database for, and the protocol. No database needed.
deno test tools_test.ts protocol_test.ts

# Every tool's real SQL, run as a real `authenticated` admin against a
# throwaway Postgres built from testing/stub_schema.sql + the real migration.
docker run -d --rm --name admin_mcp_smoke -e POSTGRES_PASSWORD=smoke \
  -p 127.0.0.1:55432:5432 postgres:15
ADMIN_MCP_TEST_DB_URL=postgres://postgres:smoke@127.0.0.1:55432/postgres \
  deno test --allow-env --allow-net --allow-read smoke_test.ts
docker stop admin_mcp_smoke
```

`testing/stub_schema.sql` is a cut-down copy of the platform's schema. When a
tool starts using a new column or RPC, add it there too.

### Adding a tool

Add an entry to `tools` in `tools.ts` (name, description, `permission`,
`readOnly`, input schema, `run`), then a sample in `tools_test.ts` and a case
in `smoke_test.ts` — both fail until it has one. A tool that writes straight
to a table must call `audit(...)`; one that goes through an RPC which already
calls `log_admin_action` need not.

## Deploying

Both parts are live on the project. The migration was applied through the
Supabase connector and is recorded on the server as `20261003190225`, which is
why the file carries that version.

```sh
supabase functions deploy admin-mcp   # verify_jwt = false is set in config.toml
```

Do not use `supabase db push` on this project without checking
`supabase migration list` first: the server's migration history and
`supabase/migrations` are not fully in step, and a push would try to re-run
whatever it finds only locally.

The function reads `SUPABASE_DB_URL`, `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`, all of which Supabase provides to every Edge
Function; there is no secret to set.
