-- Execute este arquivo no SQL Editor do seu projeto Supabase.
create extension if not exists "pgcrypto";

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  plan text not null default 'free' check (plan in ('free', 'premium')),
  monthly_goal numeric(12,2) not null default 25000,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text,
  organization_id uuid not null references public.organizations on delete cascade,
  created_at timestamptz not null default now()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  role text not null default 'admin' check (role in ('admin', 'member', 'viewer')),
  primary key (organization_id, user_id)
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  name text not null,
  company text,
  service text not null,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  status text not null default 'Em andamento' check (status in ('Em andamento', 'Concluído', 'Aguardando')),
  payment_status text not null default 'Pendente' check (payment_status in ('Pago', 'Pendente', 'Parcial')),
  due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.is_organization_member(target_organization uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.organization_members
    where organization_id = target_organization and user_id = auth.uid()
  );
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare new_organization_id uuid;
begin
  insert into public.organizations (name)
  values (coalesce(new.raw_user_meta_data ->> 'organization_name', 'Minha empresa'))
  returning id into new_organization_id;
  insert into public.profiles (id, full_name, organization_id)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new_organization_id);
  insert into public.organization_members (organization_id, user_id, role)
  values (new_organization_id, new.id, 'admin');
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
create trigger clients_updated_at before update on public.clients
  for each row execute procedure public.touch_updated_at();

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_members enable row level security;
alter table public.clients enable row level security;

create policy "members can read organizations" on public.organizations for select using (public.is_organization_member(id));
create policy "users can read own profile" on public.profiles for select using (id = auth.uid());
create policy "members can read members" on public.organization_members for select using (public.is_organization_member(organization_id));
create policy "members can read clients" on public.clients for select using (public.is_organization_member(organization_id));
create policy "members can add clients" on public.clients for insert with check (public.is_organization_member(organization_id));
create policy "members can update clients" on public.clients for update using (public.is_organization_member(organization_id)) with check (public.is_organization_member(organization_id));
create policy "members can delete clients" on public.clients for delete using (public.is_organization_member(organization_id));
