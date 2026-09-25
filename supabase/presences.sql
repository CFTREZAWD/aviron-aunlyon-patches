-- ════════════════════════════════════════════════════════════════
-- AvironCoach — Présences aux séances (style SportMember)
-- À exécuter UNE FOIS dans Supabase : SQL Editor → New query → coller → Run
-- Le script peut être relancé sans risque.
-- ════════════════════════════════════════════════════════════════

-- 1. Table des réponses (une réponse par athlète et par séance)
--    Les types de event_id / athlete_id s'adaptent automatiquement aux tables existantes.
do $$
declare
  ev_type text;
  ath_type text;
begin
  select format_type(atttypid, atttypmod) into ev_type
    from pg_attribute where attrelid = 'public.cal_events'::regclass and attname = 'id';
  select format_type(atttypid, atttypmod) into ath_type
    from pg_attribute where attrelid = 'public.athletes'::regclass and attname = 'id';

  execute format($f$
    create table if not exists public.presences (
      id uuid primary key default gen_random_uuid(),
      event_id %s not null references public.cal_events(id) on delete cascade,
      athlete_id %s not null references public.athletes(id) on delete cascade,
      statut text not null check (statut in ('present','incertain','absent')),
      commentaire text,
      updated_at timestamptz not null default now(),
      unique (event_id, athlete_id)
    )$f$, ev_type, ath_type);
end $$;

-- 2. Sécurité (RLS)
alter table public.presences enable row level security;

-- Tout membre connecté peut voir les réponses (pour savoir qui vient)
drop policy if exists presences_select on public.presences;
create policy presences_select on public.presences
  for select to authenticated using (true);

-- Un athlète ne peut modifier QUE sa propre réponse ; coachs et admins peuvent tout modifier
drop policy if exists presences_write on public.presences;
create policy presences_write on public.presences
  for all to authenticated
  using (
    exists (select 1 from public.athletes a where a.id = presences.athlete_id and a.user_id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('coach','admin'))
  )
  with check (
    exists (select 1 from public.athletes a where a.id = presences.athlete_id and a.user_id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('coach','admin'))
  );

-- 3. Noms des participants d'une séance (pour que les athlètes voient qui vient,
--    sans leur donner accès aux fiches complètes des autres). Les commentaires restent réservés au coach.
create or replace function public.presences_event(p_event_id text)
returns table (athlete_id text, prenom text, nom text, statut text)
language sql
security definer
set search_path = public
as $$
  select pr.athlete_id::text, a.prenom::text, a.nom::text, pr.statut
  from public.presences pr
  join public.athletes a on a.id = pr.athlete_id
  where pr.event_id::text = p_event_id
    and auth.uid() is not null
  order by a.prenom, a.nom;
$$;

grant execute on function public.presences_event(text) to authenticated;
