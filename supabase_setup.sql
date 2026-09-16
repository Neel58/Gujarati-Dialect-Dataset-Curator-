-- Run this in Supabase Dashboard -> SQL Editor

-- 1. Create contributors table
create table if not exists contributors (
  id uuid primary key references auth.users(id),
  name text not null,
  age int not null,
  place text not null,
  dialect text not null,
  created_at timestamptz not null default now()
);

-- Enable RLS for contributors
alter table contributors enable row level security;

create policy "Allow insert own profile" on contributors
  for insert to anon
  with check (auth.uid() = id);

create policy "Allow update own profile" on contributors
  for update to anon
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "Allow read own profile" on contributors
  for select to anon
  using (auth.uid() = id);

-- 2. Create recordings table
create table if not exists recordings (
  id uuid primary key default gen_random_uuid(),
  prompt text not null,
  storage_path text not null,
  
  -- The person holding the phone
  operator_id uuid not null references contributors(id),
  
  -- The metadata for the voice IN the recording (denormalized at insert time)
  speaker_name text not null,
  speaker_age int not null,
  speaker_place text not null,
  speaker_dialect text not null,

  created_at timestamptz not null default now()
);

-- Enable RLS for recordings
alter table recordings enable row level security;

create policy "Allow anon insert own recordings" on recordings
  for insert to anon
  with check (auth.uid() = operator_id);

create policy "Allow anon read all recordings" on recordings
  for select to anon
  using (true);