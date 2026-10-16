-- Balance: trip cover photos (one-time setup)
-- Paste into Supabase → SQL Editor → New query → Run. Safe to run more than once.

-- 1. Where the cover lives on each trip
alter table public.trips add column if not exists cover_url text;

-- 2. A public storage bucket for cover images (anyone with the link can view; only members can upload)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trip-covers', 'trip-covers', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 3. Only members of a trip can upload into that trip's folder (files are saved as <trip_id>/cover-<time>.jpg)
drop policy if exists "trip members upload covers" on storage.objects;
create policy "trip members upload covers" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'trip-covers'
    and exists (
      select 1 from public.trip_members tm
      where tm.trip_id::text = (storage.foldername(name))[1]
        and tm.user_id = auth.uid()
    )
  );

-- 4. Set a trip's cover. Checks membership itself, so it works no matter how the trips table's own rules are set up.
create or replace function public.set_trip_cover(p_trip_id uuid, p_cover_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.trip_members
    where trip_id = p_trip_id and user_id = auth.uid()
  ) then
    raise exception 'Only trip members can change the cover';
  end if;
  if p_cover_url is not null
     and p_cover_url not like '%/storage/v1/object/public/trip-covers/' || p_trip_id::text || '/%' then
    raise exception 'Cover must be uploaded to this trip''s folder';
  end if;
  update public.trips set cover_url = p_cover_url where id = p_trip_id;
end;
$$;

revoke all on function public.set_trip_cover(uuid, text) from public;
grant execute on function public.set_trip_cover(uuid, text) to authenticated;
