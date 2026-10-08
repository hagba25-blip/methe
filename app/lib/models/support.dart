/// Support client : questions fréquentes et demandes d'aide.
enum TicketCategory {
  deposit('Dépôt'),
  withdrawal('Retrait'),
  bet('Pari'),
  account('Mon compte'),
  technical('Problème technique'),
  other('Autre');

  const TicketCategory(this.label);
  final String label;

  static TicketCategory parse(String s) => values.firstWhere((v) => v.name == s, orElse: () => other);
}

enum TicketStatus {
  open('En attente du support'),
  answered('Répondu'),
  resolved('Résolu'),
  closed('Fermé');

  const TicketStatus(this.label);
  final String label;

  /// Libellé côté équipe : « open » = à traiter.
  String get staffLabel => this == open ? 'À traiter' : label;
  bool get isActive => this == open || this == answered;

  static TicketStatus parse(String s) => values.firstWhere((v) => v.name == s, orElse: () => open);
}

const faqCategoryLabels = {
  'account': 'Mon compte',
  'deposit': 'Dépôts',
  'withdrawal': 'Retraits',
  'games': 'Jeux',
  'security': 'Sécurité',
};

class FaqEntry {
  const FaqEntry({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    this.sortOrder = 100,
    this.isPublished = true,
  });

  final int id;
  final String category;
  final String question;
  final String answer;
  final int sortOrder;
  final bool isPublished;

  String get categoryLabel => faqCategoryLabels[category] ?? category;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || question.toLowerCase().contains(q) || answer.toLowerCase().contains(q);
  }

  factory FaqEntry.fromJson(Map<String, dynamic> j) => FaqEntry(
    id: j['id'] as int,
    category: j['category'] as String,
    question: j['question'] as String,
    answer: j['answer'] as String,
    sortOrder: (j['sort_order'] as int?) ?? 100,
    isPublished: (j['is_published'] as bool?) ?? true,
  );
}

class HelpCenter {
  const HelpCenter({required this.faq, this.whatsappUrl, this.hours});
  final List<FaqEntry> faq;
  final String? whatsappUrl;
  final String? hours;

  factory HelpCenter.fromJson(Map<String, dynamic> j) {
    final contact = (j['contact'] as Map<String, dynamic>?) ?? const {};
    return HelpCenter(
      faq: [for (final f in j['faq'] as List) FaqEntry.fromJson(f as Map<String, dynamic>)],
      whatsappUrl: contact['whatsapp_url'] as String?,
      hours: contact['hours'] as String?,
    );
  }
}

class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.isStaff,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });
  final int id;
  final bool isStaff;
  final String authorName;
  final String body;
  final DateTime createdAt;

  factory TicketMessage.fromJson(Map<String, dynamic> j) => TicketMessage(
    id: j['id'] as int,
    isStaff: j['is_staff'] as bool,
    authorName: j['author_name'] as String,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

class Ticket {
  const Ticket({
    required this.id,
    required this.reference,
    required this.category,
    required this.subject,
    required this.status,
    required this.unread,
    required this.lastMessageAt,
    required this.createdAt,
    this.relatedReference,
    this.clientId,
    this.clientName,
    this.assignedName,
    this.messages = const [],
  });

  final String id;
  final String reference;
  final TicketCategory category;
  final String subject;
  final String? relatedReference;
  final TicketStatus status;
  final int unread;
  final DateTime lastMessageAt;
  final DateTime createdAt;
  final String? clientId;
  final String? clientName;
  final String? assignedName;
  final List<TicketMessage> messages;

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
    id: j['id'] as String,
    reference: j['reference'] as String,
    category: TicketCategory.parse(j['category'] as String),
    subject: j['subject'] as String,
    relatedReference: j['related_reference'] as String?,
    status: TicketStatus.parse(j['status'] as String),
    unread: j['unread'] as int,
    lastMessageAt: DateTime.parse(j['last_message_at'] as String).toLocal(),
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    clientId: j['client_id'] as String?,
    clientName: j['client_name'] as String?,
    assignedName: j['assigned_name'] as String?,
    messages: [
      for (final m in (j['messages'] as List?) ?? const []) TicketMessage.fromJson(m as Map<String, dynamic>),
    ],
  );
}

/// Filtres de la file de l'équipe support.
enum SupportQueue {
  todo('À traiter'),
  answered('Répondu'),
  done('Terminé'),
  all('Toutes');

  const SupportQueue(this.label);
  final String label;
}
