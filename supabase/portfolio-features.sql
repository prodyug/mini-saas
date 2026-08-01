-- Execute after supabase/schema.sql. This migration preserves existing data.
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  client_id uuid not null references public.clients on delete cascade,
  title text not null,
  description text,
  status text not null default 'Planejamento' check (status in ('Planejamento', 'Em andamento', 'Revisão', 'Concluído')),
  amount numeric(12,2) not null default 0 check (amount >= 0),
  due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  client_id uuid not null references public.clients on delete cascade,
  project_id uuid references public.projects on delete set null,
  description text not null,
  amount numeric(12,2) not null check (amount > 0),
  status text not null default 'Pendente' check (status in ('Recebido', 'Pendente', 'Vencido')),
  due_date date,
  received_at date,
  created_at timestamptz not null default now()
);

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  email text not null,
  role text not null default 'member' check (role in ('admin', 'member', 'viewer')),
  invited_by uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique (organization_id, email)
);

create index if not exists projects_organization_id_idx on public.projects(organization_id);
create index if not exists payments_organization_id_idx on public.payments(organization_id);
create index if not exists invitations_organization_id_idx on public.invitations(organization_id);

create or replace function public.is_organization_admin(target_organization uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.organization_members where organization_id = target_organization and user_id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_organization_editor(target_organization uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.organization_members where organization_id = target_organization and user_id = auth.uid() and role in ('admin', 'member'));
$$;

create or replace function public.enforce_free_client_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare organization_plan text; client_total integer;
begin
  select plan into organization_plan from public.organizations where id = new.organization_id;
  if organization_plan = 'free' then
    select count(*) into client_total from public.clients where organization_id = new.organization_id;
    if client_total >= 10 then raise exception 'O plano gratuito permite no máximo 10 clientes. Faça upgrade para o Pro.'; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists clients_free_limit on public.clients;
create trigger clients_free_limit before insert on public.clients for each row execute procedure public.enforce_free_client_limit();

drop trigger if exists projects_updated_at on public.projects;
create trigger projects_updated_at before update on public.projects for each row execute procedure public.touch_updated_at();

-- New sign-ups consume an invitation automatically; otherwise a new organization is created.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare new_organization_id uuid; invite_role text;
begin
  select organization_id, role into new_organization_id, invite_role from public.invitations
    where lower(email) = lower(new.email) and accepted_at is null order by created_at desc limit 1;
  if new_organization_id is null then
    insert into public.organizations (name) values (coalesce(new.raw_user_meta_data ->> 'organization_name', 'Minha empresa')) returning id into new_organization_id;
    invite_role := 'admin';
  else
    update public.invitations set accepted_at = now() where organization_id = new_organization_id and lower(email) = lower(new.email) and accepted_at is null;
  end if;
  insert into public.profiles (id, full_name, organization_id) values (new.id, new.raw_user_meta_data ->> 'full_name', new_organization_id);
  insert into public.organization_members (organization_id, user_id, role) values (new_organization_id, new.id, coalesce(invite_role, 'member'));
  return new;
end;
$$;

alter table public.projects enable row level security;
alter table public.payments enable row level security;
alter table public.invitations enable row level security;

create policy "members can read projects" on public.projects for select using (public.is_organization_member(organization_id));
create policy "members can add projects" on public.projects for insert with check (public.is_organization_editor(organization_id));
create policy "members can update projects" on public.projects for update using (public.is_organization_editor(organization_id));
create policy "members can delete projects" on public.projects for delete using (public.is_organization_editor(organization_id));
create policy "members can read payments" on public.payments for select using (public.is_organization_member(organization_id));
create policy "members can add payments" on public.payments for insert with check (public.is_organization_editor(organization_id));
create policy "members can update payments" on public.payments for update using (public.is_organization_editor(organization_id));
create policy "members can delete payments" on public.payments for delete using (public.is_organization_editor(organization_id));
create policy "admins can read invitations" on public.invitations for select using (public.is_organization_admin(organization_id));
create policy "admins can create invitations" on public.invitations for insert with check (public.is_organization_admin(organization_id));
create policy "admins can delete invitations" on public.invitations for delete using (public.is_organization_admin(organization_id));
create policy "admins can update organization" on public.organizations for update using (public.is_organization_admin(id));
create policy "members can read colleague profiles" on public.profiles for select using (public.is_organization_member(organization_id));

-- Replace the initial broad client write policies so viewers remain read-only.
drop policy if exists "members can add clients" on public.clients;
drop policy if exists "members can update clients" on public.clients;
drop policy if exists "members can delete clients" on public.clients;
create policy "editors can add clients" on public.clients for insert with check (public.is_organization_editor(organization_id));
create policy "editors can update clients" on public.clients for update using (public.is_organization_editor(organization_id)) with check (public.is_organization_editor(organization_id));
create policy "editors can delete clients" on public.clients for delete using (public.is_organization_editor(organization_id));
