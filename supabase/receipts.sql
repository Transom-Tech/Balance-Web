-- Balance: receipt photos (one-time setup)
-- Paste into Supabase → SQL Editor → New query → Run. Safe to run more than once.
-- Receipts are PRIVATE: only members of the trip can upload or view them.

-- 1. Where an expense's receipt lives (a path inside the private bucket)
alter table public.expenses add column if not exists receipt_path text;

-- 2. A private storage bucket (no public links; the app asks for short-lived signed links)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 3. Trip members can upload into, and view from, their trip's folder (<trip_id>/...)
drop policy if exists "trip members upload receipts" on storage.objects;
create policy "trip members upload receipts" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and exists (
      select 1 from public.trip_members tm
      where tm.trip_id::text = (storage.foldername(name))[1]
        and tm.user_id = auth.uid()
    )
  );

drop policy if exists "trip members view receipts" on storage.objects;
create policy "trip members view receipts" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'receipts'
    and exists (
      select 1 from public.trip_members tm
      where tm.trip_id::text = (storage.foldername(name))[1]
        and tm.user_id = auth.uid()
    )
  );

-- 4. Attach (or clear, with null) a receipt on an expense. Checks membership and that the file is in that trip's folder.
create or replace function public.set_expense_receipt(p_expense_id uuid, p_receipt_path text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_trip uuid;
begin
  select trip_id into v_trip from public.expenses where id = p_expense_id;
  if v_trip is null then raise exception 'Expense not found'; end if;
  if not exists (
    select 1 from public.trip_members where trip_id = v_trip and user_id = auth.uid()
  ) then
    raise exception 'Only trip members can attach receipts';
  end if;
  if p_receipt_path is not null and p_receipt_path not like v_trip::text || '/%' then
    raise exception 'Receipt must be in this trip''s folder';
  end if;
  update public.expenses set receipt_path = p_receipt_path where id = p_expense_id;
end;
$$;

revoke all on function public.set_expense_receipt(uuid, text) from public;
grant execute on function public.set_expense_receipt(uuid, text) to authenticated;
