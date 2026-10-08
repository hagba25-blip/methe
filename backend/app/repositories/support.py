"""Support client : questions fréquentes et demandes d'aide (tickets)."""

from uuid import UUID

from psycopg import AsyncConnection

# Vue joueur (unread = réponses de l'équipe non lues) ou équipe (messages du joueur non lus).
TICKET_COLUMNS = """
  t.id, t.reference, t.category, t.subject, t.related_reference, t.status,
  case when %(staff)s then t.staff_unread else t.user_unread end as unread,
  t.last_message_at, t.created_at,
  case when %(staff)s then p.public_id end as client_id,
  case when %(staff)s then p.first_name || ' ' || p.last_name end as client_name,
  case when %(staff)s then a.first_name || ' ' || a.last_name end as assigned_name
"""
TICKET_FROM = """
  from public.support_tickets t
  join public.profiles p on p.id = t.user_id
  left join public.profiles a on a.id = t.assigned_to
"""

# Filtres de la file d'attente de l'équipe
QUEUE_STATES = {
    "todo": ("open",),
    "answered": ("answered",),
    "done": ("resolved", "closed"),
    "all": ("open", "answered", "resolved", "closed"),
}


async def faq(conn: AsyncConnection, language: str) -> list[dict]:
    cur = await conn.execute(
        """
        select id, category, question, answer from public.faq_entries
        where is_published
          and language_code = case when exists (select 1 from public.faq_entries
                                                 where is_published and language_code = %(lang)s)
                                   then %(lang)s else 'fr' end
        order by array_position(array['account','deposit','withdrawal','games','security'], category), sort_order, id
        """,
        {"lang": language},
    )
    return await cur.fetchall()


async def contact_settings(conn: AsyncConnection) -> dict:
    cur = await conn.execute(
        "select key, value from public.app_settings where key in ('support.whatsapp_number', 'support.hours')")
    return {r["key"]: r["value"] for r in await cur.fetchall()}


async def list_for_user(conn: AsyncConnection, user_id: UUID, limit: int) -> list[dict]:
    cur = await conn.execute(
        f"select {TICKET_COLUMNS} {TICKET_FROM} where t.user_id = %(user)s order by t.last_message_at desc limit %(limit)s",
        {"staff": False, "user": user_id, "limit": limit},
    )
    return await cur.fetchall()


async def queue(conn: AsyncConnection, state: str, client_id: str | None, limit: int, before) -> list[dict]:
    """File de l'équipe : les plus anciennes demandes à traiter d'abord, sinon les plus récentes."""
    oldest_first = state == "todo"
    cur = await conn.execute(
        f"""
        select {TICKET_COLUMNS} {TICKET_FROM}
        where t.status = any(%(states)s)
          and (%(client)s::text is null or p.public_id = %(client)s::text)
          and (%(before)s::timestamptz is null
               or (case when %(asc)s then t.last_message_at > %(before)s else t.last_message_at < %(before)s end))
        order by case when %(asc)s then t.last_message_at end asc,
                 case when not %(asc)s then t.last_message_at end desc
        limit %(limit)s
        """,
        {"staff": True, "states": list(QUEUE_STATES[state]), "client": client_id, "before": before,
         "asc": oldest_first, "limit": limit},
    )
    return await cur.fetchall()


async def get(conn: AsyncConnection, ticket_id: UUID, *, staff: bool, user_id: UUID | None = None) -> dict | None:
    """Demande et ses messages ; pour un joueur, uniquement la sienne. Marque les messages comme lus."""
    cur = await conn.execute(
        f"select {TICKET_COLUMNS} {TICKET_FROM} where t.id = %(id)s and (%(staff)s or t.user_id = %(user)s)",
        {"staff": staff, "id": ticket_id, "user": user_id},
    )
    ticket = await cur.fetchone()
    if ticket is None:
        return None
    column = "staff_unread" if staff else "user_unread"
    await conn.execute(f"update public.support_tickets set {column} = 0 where id = %s and {column} > 0", (ticket_id,))
    cur = await conn.execute(
        """
        select m.id, m.is_staff, m.body, m.created_at,
               case when %(staff)s then a.first_name || ' ' || a.last_name
                    when m.is_staff then 'Support · ' || a.first_name
                    else a.first_name end as author_name
        from public.support_messages m join public.profiles a on a.id = m.author_id
        where m.ticket_id = %(id)s order by m.id
        """,
        {"staff": staff, "id": ticket_id},
    )
    return {**ticket, "messages": await cur.fetchall()}


async def open_ticket(conn: AsyncConnection, user_id: UUID, category: str, subject: str, message: str,
                      related_reference: str | None) -> UUID:
    cur = await conn.execute("select id from private.open_support_ticket(%s, %s, %s, %s, %s)",
                             (user_id, category, subject, message, related_reference))
    return (await cur.fetchone())["id"]


async def post_message(conn: AsyncConnection, ticket_id: UUID, author_id: UUID, as_staff: bool, body: str) -> None:
    await conn.execute("select private.post_support_message(%s, %s, %s, %s)", (ticket_id, author_id, as_staff, body))


async def set_status(conn: AsyncConnection, ticket_id: UUID, actor_id: UUID, as_staff: bool, status: str) -> None:
    await conn.execute("select private.set_support_status(%s, %s, %s, %s)", (ticket_id, actor_id, as_staff, status))


# FAQ (administration) -----------------------------------------------------------------
FAQ_ADMIN_COLUMNS = "id, category, question, answer, language_code, sort_order, is_published, updated_at"


async def faq_all(conn: AsyncConnection) -> list[dict]:
    cur = await conn.execute(
        f"select {FAQ_ADMIN_COLUMNS} from public.faq_entries order by language_code, "
        "array_position(array['account','deposit','withdrawal','games','security'], category), sort_order, id")
    return await cur.fetchall()


async def faq_create(conn: AsyncConnection, admin_id: UUID, data: dict) -> dict:
    cur = await conn.execute(
        f"""
        insert into public.faq_entries (category, question, answer, language_code, sort_order, is_published, updated_by)
        values (%(category)s, trim(%(question)s), trim(%(answer)s), %(language_code)s, %(sort_order)s,
                %(is_published)s, %(admin)s)
        returning {FAQ_ADMIN_COLUMNS}
        """,
        {**data, "admin": admin_id},
    )
    return await cur.fetchone()


async def faq_update(conn: AsyncConnection, faq_id: int, admin_id: UUID, changes: dict) -> dict | None:
    sets = ", ".join(f"{k} = %({k})s" for k in changes)
    cur = await conn.execute(
        f"update public.faq_entries set {sets}{', ' if sets else ''}updated_by = %(admin)s "
        f"where id = %(id)s returning {FAQ_ADMIN_COLUMNS}",
        {**changes, "admin": admin_id, "id": faq_id},
    )
    return await cur.fetchone()


async def faq_delete(conn: AsyncConnection, faq_id: int) -> bool:
    cur = await conn.execute("delete from public.faq_entries where id = %s", (faq_id,))
    return cur.rowcount > 0
