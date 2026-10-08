import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/support.dart';

void main() {
  test('demande et conversation', () {
    final t = Ticket.fromJson({
      'id': 't1', 'reference': 'SUP-20261008-000001', 'category': 'withdrawal', 'subject': 'Retrait en attente',
      'related_reference': 'WDR-20261008-000001', 'status': 'answered', 'unread': 1,
      'last_message_at': '2026-10-08T10:05:00Z', 'created_at': '2026-10-08T10:00:00Z',
      'client_id': null, 'client_name': null, 'assigned_name': null,
      'messages': [
        {'id': 1, 'is_staff': false, 'author_name': 'Hubert', 'body': 'Bonjour', 'created_at': '2026-10-08T10:00:00Z'},
        {'id': 2, 'is_staff': true, 'author_name': 'Support · Yao', 'body': 'On vérifie', 'created_at': '2026-10-08T10:05:00Z'},
      ],
    });
    expect(t.category.label, 'Retrait');
    expect(t.status.label, 'Répondu');
    expect(t.status.isActive, isTrue);
    expect(t.messages.last.isStaff, isTrue);
    expect(TicketStatus.parse('open').staffLabel, 'À traiter');
    expect(TicketCategory.parse('???'), TicketCategory.other);
  });

  test('aide : FAQ, recherche et contact', () {
    final h = HelpCenter.fromJson({
      'faq': [
        {'id': 1, 'category': 'deposit', 'question': 'Comment déposer ?', 'answer': 'Touchez DÉPOSER.'},
        {'id': 2, 'category': 'games', 'question': 'Le Lonato ?', 'answer': '5 numéros parmi 90.'},
      ],
      'contact': {'whatsapp_url': null, 'hours': 'Tous les jours'},
    });
    expect(h.faq.first.categoryLabel, 'Dépôts');
    expect(h.faq.where((f) => f.matches('lonato')).map((f) => f.id), [2]);
    expect(h.faq.where((f) => f.matches('')).length, 2);
    expect(h.whatsappUrl, isNull);
    expect(h.hours, 'Tous les jours');
  });
}
