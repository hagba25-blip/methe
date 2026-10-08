-- =============================================================================
-- 0007 — Nomination d'un administrateur (à lancer depuis le SQL Editor Supabase)
-- =============================================================================
-- Usage : select private.grant_staff_role('vous@example.com', 'super_admin');
-- La personne doit d'abord avoir créé son compte dans l'application.

create or replace function private.grant_staff_role(p_email text, p_role public.app_role)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
begin
  select * into v_profile from public.profiles where email = lower(trim(p_email));
  if not found then
    raise exception 'Aucun compte avec l''e-mail %', p_email;
  end if;
  insert into public.admin_users (user_id, role, is_active)
  values (v_profile.id, p_role, true)
  on conflict (user_id) do update set role = excluded.role, is_active = true;
  insert into public.audit_logs (actor_id, action, entity, entity_id, new_data)
  values (null, 'grant_staff_role', 'admin_users', v_profile.id::text,
          jsonb_build_object('role', p_role, 'public_id', v_profile.public_id));
  return format('%s %s (ID %s) est maintenant %s', v_profile.first_name, v_profile.last_name,
                v_profile.public_id, p_role);
end $$;

create or replace function private.revoke_staff_role(p_email text)
returns void language sql security definer set search_path = '' as $$
  update public.admin_users set is_active = false
  where user_id = (select id from public.profiles where email = lower(trim(p_email)));
$$;

revoke execute on function private.grant_staff_role(text, public.app_role) from public, anon, authenticated;
revoke execute on function private.revoke_staff_role(text) from public, anon, authenticated;
