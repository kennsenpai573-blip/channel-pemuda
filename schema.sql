-- PEMUDA CHANNEL / Supabase PostgreSQL schema
-- Jalankan seluruh file di Supabase Dashboard > SQL Editor > New query.
-- RLS wajib aktif. Jangan pernah menaruh service_role/secret key di frontend.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Pengguna',
  avatar_url text,
  bio text not null default '',
  role text not null default 'user' check (role in ('user','admin','owner')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name',''), split_part(new.email,'@',1), 'Pengguna'))
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Prevent ordinary users from changing their own role.
create or replace function public.protect_profile_role()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.role is distinct from old.role and current_user not in ('postgres','supabase_admin') and coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'Role changes must be performed by a trusted administrator';
  end if;
  new.updated_at = now();
  return new;
end; $$;
drop trigger if exists protect_profile_role_trigger on public.profiles;
create trigger protect_profile_role_trigger before update on public.profiles
for each row execute procedure public.protect_profile_role();

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 60),
  slug text not null unique,
  description text not null default '' check (char_length(description) <= 500),
  category text not null default 'Komunitas',
  icon text not null default '✦',
  cover_url text,
  privacy text not null default 'public' check (privacy in ('public','private')),
  status text not null default 'active' check (status in ('active','suspended','deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.channel_followers (
  channel_id uuid not null references public.channels(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (channel_id,user_id)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 10000),
  media_url text,
  media_type text check (media_type in ('image','video','audio','file') or media_type is null),
  status text not null default 'published' check (status in ('draft','published','hidden','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  status text not null default 'published' check (status in ('published','hidden','removed')),
  created_at timestamptz not null default now()
);

create table if not exists public.post_reactions (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null default 'like' check (reaction in ('like','love','laugh','wow','sad')),
  created_at timestamptz not null default now(),
  primary key (post_id,user_id)
);

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  description text not null default '' check (char_length(description) <= 5000),
  video_url text,
  thumbnail_url text,
  visibility text not null default 'public' check (visibility in ('public','private','unlisted')),
  status text not null default 'published' check (status in ('draft','published','hidden','removed')),
  views bigint not null default 0 check (views >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null check (type in ('follow','comment','reaction','mention','system','report_update')),
  title text not null,
  body text not null default '',
  target_type text,
  target_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('channel','post','comment','video','profile')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 3 and 1000),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  moderator_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists channels_owner_idx on public.channels(owner_id);
create index if not exists channels_public_idx on public.channels(privacy,status,created_at desc);
create index if not exists followers_user_idx on public.channel_followers(user_id,created_at desc);
create index if not exists posts_channel_idx on public.posts(channel_id,created_at desc);
create index if not exists comments_post_idx on public.comments(post_id,created_at);
create index if not exists notifications_user_idx on public.notifications(user_id,created_at desc);
create index if not exists reports_status_idx on public.reports(status,created_at desc);

-- SECURITY DEFINER helpers avoid recursive RLS checks between channels and followers.
create or replace function public.is_channel_member(target_channel uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.channel_followers f where f.channel_id=target_channel and f.user_id=(select auth.uid()));
$$;
create or replace function public.is_channel_owner(target_channel uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.channels c where c.id=target_channel and c.owner_id=(select auth.uid()));
$$;

-- Helper avoids recursive profile-policy checks and is intentionally read-only.
create or replace function public.current_profile_role()
returns text language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = (select auth.uid()) limit 1;
$$;

alter table public.profiles enable row level security;
alter table public.channels enable row level security;
alter table public.channel_followers enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.post_reactions enable row level security;
alter table public.videos enable row level security;
alter table public.notifications enable row level security;
alter table public.reports enable row level security;

-- Profiles: public profile basics readable; each user edits only their own non-role fields.
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to authenticated using (true);
drop policy if exists "profile owner update" on public.profiles;
create policy "profile owner update" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Channels: public active channels are discoverable; owners manage their own channels; admins/owner can moderate.
drop policy if exists "public channels readable" on public.channels;
create policy "public channels readable" on public.channels for select to anon, authenticated using ((privacy = 'public' and status = 'active') or owner_id = (select auth.uid()) or public.current_profile_role() in ('admin','owner') or public.is_channel_member(id));
drop policy if exists "authenticated create channel" on public.channels;
create policy "authenticated create channel" on public.channels for insert to authenticated with check (owner_id = (select auth.uid()));
drop policy if exists "owner update channel" on public.channels;
create policy "owner update channel" on public.channels for update to authenticated using (owner_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner')) with check (owner_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "owner delete channel" on public.channels;
create policy "owner delete channel" on public.channels for delete to authenticated using (owner_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));

-- Followers: follow/unfollow only for self; private-channel members can see membership rows only where allowed by channel visibility.
drop policy if exists "followers visible to self or channel owner" on public.channel_followers;
create policy "followers visible to self or channel owner" on public.channel_followers for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.channels c where c.id=channel_id and (c.owner_id=(select auth.uid()) or c.privacy='public')) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "follow as self" on public.channel_followers;
create policy "follow as self" on public.channel_followers for insert to authenticated with check (user_id=(select auth.uid()) and exists(select 1 from public.channels c where c.id=channel_id and c.status='active'));
drop policy if exists "unfollow as self" on public.channel_followers;
create policy "unfollow as self" on public.channel_followers for delete to authenticated using (user_id=(select auth.uid()));

-- Posts: visible in public channels or private channels to followers/owner; author can create/edit own posts.
drop policy if exists "published posts readable" on public.posts;
create policy "published posts readable" on public.posts for select to anon, authenticated using (status='published' and exists(select 1 from public.channels c where c.id=channel_id and c.status='active' and (c.privacy='public' or c.owner_id=(select auth.uid()) or public.is_channel_member(c.id))) or author_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "channel owner creates posts" on public.posts;
create policy "channel owner creates posts" on public.posts for insert to authenticated with check (author_id=(select auth.uid()) and exists(select 1 from public.channels c where c.id=channel_id and c.owner_id=(select auth.uid())));
drop policy if exists "author or moderator updates posts" on public.posts;
create policy "author or moderator updates posts" on public.posts for update to authenticated using (author_id=(select auth.uid()) or exists(select 1 from public.channels c where c.id=channel_id and c.owner_id=(select auth.uid())) or public.current_profile_role() in ('admin','owner')) with check (author_id=(select auth.uid()) or exists(select 1 from public.channels c where c.id=channel_id and c.owner_id=(select auth.uid())) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "author or moderator deletes posts" on public.posts;
create policy "author or moderator deletes posts" on public.posts for delete to authenticated using (author_id=(select auth.uid()) or exists(select 1 from public.channels c where c.id=channel_id and c.owner_id=(select auth.uid())) or public.current_profile_role() in ('admin','owner'));

-- Comments / reactions: authenticated users may write only as themselves, and only to visible posts.
drop policy if exists "comments readable" on public.comments;
create policy "comments readable" on public.comments for select to anon, authenticated using (status='published' and exists(select 1 from public.posts p where p.id=post_id));
drop policy if exists "comment as self" on public.comments;
create policy "comment as self" on public.comments for insert to authenticated with check (author_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id and p.status='published'));
drop policy if exists "comment author or moderator update" on public.comments;
create policy "comment author or moderator update" on public.comments for update to authenticated using (author_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner')) with check (author_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "comment author or moderator delete" on public.comments;
create policy "comment author or moderator delete" on public.comments for delete to authenticated using (author_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "reactions readable" on public.post_reactions;
create policy "reactions readable" on public.post_reactions for select to anon, authenticated using (exists(select 1 from public.posts p where p.id=post_id and p.status='published'));
drop policy if exists "reaction as self" on public.post_reactions;
create policy "reaction as self" on public.post_reactions for insert to authenticated with check (user_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id and p.status='published'));
drop policy if exists "reaction owner delete" on public.post_reactions;
create policy "reaction owner delete" on public.post_reactions for delete to authenticated using (user_id=(select auth.uid()));

-- Videos
 drop policy if exists "public videos readable" on public.videos;
create policy "public videos readable" on public.videos for select to anon, authenticated using ((visibility='public' and status='published') or owner_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner') or (visibility='unlisted' and status='published'));
drop policy if exists "video owner insert" on public.videos;
create policy "video owner insert" on public.videos for insert to authenticated with check (owner_id=(select auth.uid()) and exists(select 1 from public.channels c where c.id=channel_id and c.owner_id=(select auth.uid())));
drop policy if exists "video owner update delete" on public.videos;
create policy "video owner update delete" on public.videos for all to authenticated using (owner_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner')) with check (owner_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));

-- Notifications and reports are private to their owner / moderators.
drop policy if exists "own notifications" on public.notifications;
create policy "own notifications" on public.notifications for select to authenticated using (user_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "own notification update" on public.notifications;
create policy "own notification update" on public.notifications for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
drop policy if exists "reporter creates report" on public.reports;
create policy "reporter creates report" on public.reports for insert to authenticated with check (reporter_id=(select auth.uid()));
drop policy if exists "reporter or moderator reads reports" on public.reports;
create policy "reporter or moderator reads reports" on public.reports for select to authenticated using (reporter_id=(select auth.uid()) or public.current_profile_role() in ('admin','owner'));
drop policy if exists "moderators manage reports" on public.reports;
create policy "moderators manage reports" on public.reports for update to authenticated using (public.current_profile_role() in ('admin','owner')) with check (public.current_profile_role() in ('admin','owner'));

-- Storage buckets: public avatars; private media bucket. Private media should be served with signed URLs.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('pc-avatars','pc-avatars',true,5242880,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('pc-media','pc-media',false,104857600,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','audio/mpeg','application/pdf'])
on conflict (id) do nothing;
drop policy if exists "avatar public read" on storage.objects;
create policy "avatar public read" on storage.objects for select to anon,authenticated using (bucket_id='pc-avatars');
drop policy if exists "avatar owner upload" on storage.objects;
create policy "avatar owner upload" on storage.objects for insert to authenticated with check (bucket_id='pc-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "avatar owner update" on storage.objects;
create policy "avatar owner update" on storage.objects for update to authenticated using (bucket_id='pc-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text) with check (bucket_id='pc-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "avatar owner delete" on storage.objects;
create policy "avatar owner delete" on storage.objects for delete to authenticated using (bucket_id='pc-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "private media owner folder" on storage.objects;
create policy "private media owner folder" on storage.objects for all to authenticated using (bucket_id='pc-media' and (storage.foldername(name))[1]=(select auth.uid())::text) with check (bucket_id='pc-media' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- IMPORTANT: after creating the first account, assign the trusted owner manually in SQL Editor:
-- update public.profiles set role='owner' where id='AUTH_USER_UUID_HERE';
-- Do not allow users to self-assign owner/admin. Test policies with a second test account before launch.
