-- Idempotent Migration for Customer Reports & Issue Resolution System
create table if not exists public.customer_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete cascade,
  subject text not null,
  description text not null,
  status text not null default 'pending', -- 'pending' | 'in_progress' | 'resolved'
  admin_reply text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Enable RLS
alter table public.customer_reports enable row level security;

-- Drop policies if exist to ensure idempotency
drop policy if exists "Users can view their own reports" on public.customer_reports;
drop policy if exists "Users can create reports" on public.customer_reports;
drop policy if exists "Admins can manage all reports" on public.customer_reports;

create policy "Users can view their own reports"
  on public.customer_reports for select
  using (auth.uid() = user_id);

create policy "Users can create reports"
  on public.customer_reports for insert
  with check (auth.uid() = user_id);

create policy "Admins can manage all reports"
  on public.customer_reports for all
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'admin'
    )
  );

-- Idempotent realtime publication addition
do $$
begin
  alter publication supabase_realtime add table public.customer_reports;
exception
  when duplicate_object then null;
end $$;
