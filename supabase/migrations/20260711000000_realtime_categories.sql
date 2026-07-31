-- Realtime for category tables so admin edits show up live in the app.
do $$ begin
  alter publication supabase_realtime add table public.vendor_categories;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
