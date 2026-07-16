-- ============================================================
-- toast 🍞 database setup
-- Run this ONCE in Supabase → SQL Editor → New query → Run
-- Admin email is set to xnavyprofx@gmail.com (change below if needed)
-- ============================================================

-- ---------- tables ----------
create table if not exists profiles (
  id uuid primary key references auth.users on delete cascade,
  name text,
  avatar text
);
alter table profiles add column if not exists avatar text;

create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  text text not null check (char_length(text) <= 200),
  subs jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);
alter table tasks add column if not exists subs jsonb default '[]'::jsonb;


create table if not exists toasts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  text text not null,
  toasted_at timestamptz default now()
);

create table if not exists feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete set null,
  message text not null check (char_length(message) <= 2000),
  created_at timestamptz default now()
);

create index if not exists toasts_user_time on toasts (user_id, toasted_at desc);

-- ---------- row level security ----------
alter table profiles enable row level security;
alter table tasks enable row level security;
alter table toasts enable row level security;
alter table feedback enable row level security;

-- who is the admin?
create or replace function is_admin() returns boolean
language sql stable as
$$ select coalesce(auth.jwt() ->> 'email', '') = 'xnavyprofx@gmail.com' $$;

-- profiles: you can only see/edit your own
create policy "own profile select" on profiles for select using (id = auth.uid());
create policy "own profile insert" on profiles for insert with check (id = auth.uid());
create policy "own profile update" on profiles for update using (id = auth.uid());

-- tasks: fully private to each user
create policy "own tasks select" on tasks for select using (user_id = auth.uid());
create policy "own tasks insert" on tasks for insert with check (user_id = auth.uid());
create policy "own tasks update" on tasks for update using (user_id = auth.uid());
create policy "own tasks delete" on tasks for delete using (user_id = auth.uid());

-- toasts: private to each user; admin can read all (for stats)
create policy "own toasts select" on toasts for select using (user_id = auth.uid() or is_admin());
create policy "own toasts insert" on toasts for insert with check (user_id = auth.uid());
create policy "own toasts delete" on toasts for delete using (user_id = auth.uid());

-- feedback: anyone may send (even guests); only admin may read
create policy "anyone sends feedback" on feedback for insert
  to anon, authenticated with check (true);
create policy "admin reads feedback" on feedback for select using (is_admin());

-- ---------- admin stats (only works for the admin) ----------
create or replace function admin_stats() returns json
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    raise exception 'not allowed';
  end if;
  return json_build_object(
    'users',        (select count(*) from auth.users),
    'toasts_total', (select count(*) from toasts),
    'toasts_today', (select count(*) from toasts where toasted_at >= date_trunc('day', now())),
    'toasts_week',  (select count(*) from toasts where toasted_at >= now() - interval '7 days'),
    'feedback',     (select count(*) from feedback)
  );
end $$;

-- ---------- delete my own account (used by Settings) ----------
create or replace function delete_me() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from auth.users where id = auth.uid();
end $$;
