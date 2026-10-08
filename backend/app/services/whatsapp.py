from urllib.parse import quote

DEFAULT_TEMPLATE = "Je veux faire dépôt sur mon compte avec ID du client : {client_id}"


def deposit_message(client_id: str, template: str | None = None) -> str:
    return (template or DEFAULT_TEMPLATE).replace("{client_id}", client_id)


def chat_url(phone: str, text: str) -> str:
    """Lien universel WhatsApp (ouvre l'application sur mobile, WhatsApp Web sinon)."""
    digits = "".join(ch for ch in phone if ch.isdigit())
    return f"https://wa.me/{digits}?text={quote(text)}"
