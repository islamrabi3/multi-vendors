-- Content the operator must be able to change without shipping a build.
--
-- Terms, the about page, the social links in its footer, and which stores are
-- promoted on the customer home were all either absent or would have been
-- compiled into the app. Each one is the kind of thing that changes for legal
-- or marketing reasons on someone else's timetable, and waiting days for an
-- App Store review to correct a phone number is not a workable answer.

-- ---------------------------------------------------------------------------
-- 1. Long-form pages: terms, privacy, about.
--
-- Bilingual columns rather than a row per locale, so a page can never exist in
-- one language and silently vanish in the other; the app falls back to the
-- English body when a translation is blank, matching the catalogue's rule.
-- ---------------------------------------------------------------------------
create table if not exists public.app_content (
  key text primary key,
  title_en text not null default '',
  title_ar text,
  body_en text not null default '',
  body_ar text,
  is_published boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table public.app_content is
  'Operator-editable long-form pages, keyed by slug (terms, privacy, about).';

drop trigger if exists trg_app_content_updated_at on public.app_content;
create trigger trg_app_content_updated_at
  before update on public.app_content
  for each row execute function public.set_updated_at();

alter table public.app_content enable row level security;

-- Terms have to be readable on the signup screen, before anyone has an
-- account, so this is one of the few genuinely public reads in the schema.
drop policy if exists app_content_read on public.app_content;
create policy app_content_read on public.app_content
  for select to anon, authenticated using (is_published or public.is_admin());

drop policy if exists app_content_admin_all on public.app_content;
create policy app_content_admin_all on public.app_content
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Seeded empty and unpublished so the app has rows to edit rather than the
-- admin having to guess the key names. Nothing is shown until an admin
-- publishes real text.
insert into public.app_content (key, title_en, title_ar, is_published)
values
  ('terms',   'Terms & Conditions', 'الشروط والأحكام', false),
  ('privacy', 'Privacy Policy',     'سياسة الخصوصية',  false),
  ('about',   'About Us',           'من نحن',          false)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Social links for the about page.
--
-- Optional by design: the about page renders whatever is active and shows no
-- footer at all when the table is empty, so a platform with no Instagram does
-- not get a dead icon.
-- ---------------------------------------------------------------------------
create table if not exists public.app_links (
  id uuid primary key default gen_random_uuid(),
  platform text not null,
  url text not null,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

comment on column public.app_links.platform is
  'Icon selector: facebook | instagram | x | tiktok | youtube | whatsapp | '
  'linkedin | website | email | phone.';

alter table public.app_links enable row level security;

drop policy if exists app_links_read on public.app_links;
create policy app_links_read on public.app_links
  for select to anon, authenticated using (is_active or public.is_admin());

drop policy if exists app_links_admin_all on public.app_links;
create policy app_links_admin_all on public.app_links
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- 3. Recommended stores.
--
-- A flag on the store rather than a separate list table: the customer home
-- already selects from `vendors`, so promotion is one predicate instead of a
-- join, and a store cannot be recommended while it no longer exists.
-- ---------------------------------------------------------------------------
alter table public.vendors
  add column if not exists is_recommended boolean not null default false,
  add column if not exists recommended_rank int not null default 0;

comment on column public.vendors.recommended_rank is
  'Ascending display order within the recommended rail; ties fall back to '
  'rating.';

-- Only ever queried for the handful of promoted rows, so the index carries the
-- predicate rather than covering the whole table.
create index if not exists vendors_recommended_idx
  on public.vendors (recommended_rank, rating_avg desc)
  where is_recommended;

-- Promotion is an operator decision, so it does not travel through the
-- vendor's own update policy.
create or replace function public.admin_set_vendor_recommended(
  p_vendor_id uuid,
  p_recommended boolean,
  p_rank int default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  update public.vendors
  set is_recommended = p_recommended,
      recommended_rank = case when p_recommended then p_rank else 0 end
  where id = p_vendor_id;
end;
$$;

revoke execute on function public.admin_set_vendor_recommended(uuid, boolean, int)
  from public, anon;
grant execute on function public.admin_set_vendor_recommended(uuid, boolean, int)
  to authenticated;
