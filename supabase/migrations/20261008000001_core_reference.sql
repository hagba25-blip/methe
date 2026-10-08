-- =============================================================================
-- 0001 — Extensions, schémas privés, données de référence (pays, devises, langues)
-- =============================================================================
-- Conventions :
--   * Tous les montants sont stockés en BIGINT, en unités mineures de la devise
--     (XOF a 0 décimale → 1 F = 1 ; USD a 2 décimales → 1 $ = 100).
--   * Le schéma `private` contient les fonctions et tables jamais exposées à l'API.
--   * Aucune table métier n'est modifiable directement par le rôle `authenticated`.
-- =============================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;  -- déjà présent sur Supabase

create schema if not exists private;
revoke all on schema private from public;

-- Horodatage automatique ------------------------------------------------------
create or replace function private.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Devises ---------------------------------------------------------------------
create table public.currencies (
  code        char(3) primary key check (code ~ '^[A-Z]{3}$'),
  name        text    not null,
  symbol      text    not null,
  decimals    smallint not null check (decimals between 0 and 4),
  is_active   boolean not null default true
);

-- Langues ---------------------------------------------------------------------
create table public.languages (
  code       varchar(5) primary key check (code ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  name       text not null,
  is_active  boolean not null default true
);

-- Pays ------------------------------------------------------------------------
create table public.countries (
  code               char(2) primary key check (code ~ '^[A-Z]{2}$'),
  name               text not null,
  dial_code          varchar(6) not null check (dial_code ~ '^\+[0-9]{1,4}$'),
  default_currency   char(3) not null references public.currencies(code),
  default_language   varchar(5) not null references public.languages(code),
  is_active          boolean not null default true
);
