-- MultiPad Zero-Knowledge Vault Schema
-- Run this script in the Supabase SQL Editor (Dashboard -> SQL Editor -> New Query)

-- 1. UUID Extension
create extension if not exists "uuid-ossp";

-- 2. User Profiles Table (Stores user public salt for PBKDF2/Argon2 key derivation)
create table if not exists public.user_profiles (
  id uuid references auth.users on delete cascade primary key,
  master_salt text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for user_profiles
alter table public.user_profiles enable row level security;

create policy "Users can read own profile"
  on public.user_profiles for select
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.user_profiles for insert
  with check (auth.uid() = id);

create policy "Users can update own profile"
  on public.user_profiles for update
  using (auth.uid() = id);

-- 3. Vault Items Table (Stores ONLY zero-knowledge encrypted blobs)
-- The server NEVER sees note titles, plaintexts, or passwords.
create table if not exists public.vault_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  item_type text not null default 'note', -- 'note' or 'credential'
  encrypted_payload text not null,       -- AES-256-GCM ciphertext (Base64)
  iv text not null,                      -- AES-GCM Initialization Vector (Base64)
  mac text not null,                     -- AES-GCM Authentication Tag (Base64)
  is_deleted boolean default false,      -- Soft delete tombstone for sync
  client_updated_at timestamp with time zone not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Indices for performance
create index if not exists idx_vault_items_user on public.vault_items(user_id);
create index if not exists idx_vault_items_updated on public.vault_items(user_id, updated_at desc);

-- Enable RLS for vault_items
alter table public.vault_items enable row level security;

create policy "Users can read own vault items"
  on public.vault_items for select
  using (auth.uid() = user_id);

create policy "Users can insert own vault items"
  on public.vault_items for insert
  with check (auth.uid() = user_id);

create policy "Users can update own vault items"
  on public.vault_items for update
  using (auth.uid() = user_id);

create policy "Users can delete own vault items"
  on public.vault_items for delete
  using (auth.uid() = user_id);

-- 4. Enable Supabase Realtime for instant synchronization across devices
alter publication supabase_realtime add table public.vault_items;
