// Tests d'écrans : chaque écran est affiché avec des données de test (sans réseau)
// et on vérifie ce que le joueur ou l'équipe voit, et les principales actions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/risk.dart';
import 'package:methe/models/support.dart';
import 'package:methe/providers/providers.dart';
import 'package:methe/repositories/admin_repository.dart';
import 'package:methe/repositories/support_repository.dart';
import 'package:methe/screens/admin/admin_risk_screen.dart';
import 'package:methe/screens/admin/admin_support_screen.dart';
import 'package:methe/screens/admin/admin_users_screen.dart';
import 'package:methe/screens/support/help_screen.dart';
import 'package:methe/screens/support/ticket_screen.dart';

Map<String, dynamic> _ticket(String id, String subject, String status, int unread, {bool staff = false, List msgs = const []}) => {
  'id': id, 'reference': 'SUP-20261008-00000$id', 'category': 'withdrawal', 'subject': subject,
  'related_reference': 'WDR-20261008-000001', 'status': status, 'unread': unread,
  'last_message_at': '2026-10-08T10:05:00Z', 'created_at': '2026-10-08T10:00:00Z',
  'client_id': staff ? '6250398825' : null, 'client_name': staff ? 'Hubert Agbo' : null, 'assigned_name': null,
  'messages': msgs,
};
const _msgs = [
  {'id': 1, 'is_staff': false, 'author_name': 'Hubert', 'body': 'Mon retrait n\'est pas arrivé.', 'created_at': '2026-10-08T10:00:00Z'},
  {'id': 2, 'is_staff': true, 'author_name': 'Support · Yao', 'body': 'Le paiement part aujourd\'hui.', 'created_at': '2026-10-08T10:05:00Z'},
];

class FakeSupport implements SupportRepository {
  final replies = <String>[];
  TicketCategory? opened;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
  @override
  Future<Ticket> ticket(String id) async => Ticket.fromJson(_ticket(id, 'Retrait en attente', 'answered', 0, msgs: _msgs));
  @override
  Future<Ticket> reply(String id, String body) async {
    replies.add(body);
    return Ticket.fromJson(_ticket(id, 'Retrait en attente', 'open', 0, msgs: [
      ..._msgs,
      {'id': 3, 'is_staff': false, 'author_name': 'Hubert', 'body': body, 'created_at': '2026-10-08T10:06:00Z'},
    ]));
  }
}

class FakeAdmin implements AdminRepository {
  final statuses = <TicketStatus>[];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
  @override
  Future<List<Ticket>> supportQueue(SupportQueue q, {String? clientId}) async => q == SupportQueue.todo
      ? [Ticket.fromJson(_ticket('1', 'Retrait en attente', 'open', 2, staff: true))]
      : [];
  @override
  Future<Ticket> supportTicket(String id) async =>
      Ticket.fromJson(_ticket(id, 'Retrait en attente', 'open', 0, staff: true, msgs: _msgs));
  @override
  Future<Ticket> supportStatus(String id, TicketStatus status) async {
    statuses.add(status);
    return Ticket.fromJson(_ticket(id, 'Retrait en attente', status.name, 0, staff: true, msgs: _msgs));
  }
  @override
  Future<List<RiskEvent>> riskEvents({String state = 'open', String? clientId, int? before, int limit = 50}) async => [
    RiskEvent.fromJson({'id': 4, 'kind': 'shared_payout_account', 'severity': 4, 'reference': 'WDR-20261008-000003',
      'details': {'payout_account': '+22890000072', 'other_accounts': ['6000000002']}, 'created_at': '2026-10-08T10:00:00Z',
      'client_id': '6000000001', 'client_name': 'Gédéon Romuald', 'client_status': 'active'}),
  ];
  @override
  Future<AdminUser> user(String publicId) async => AdminUser.fromJson({'public_id': publicId, 'first_name': 'Gédéon',
    'last_name': 'Romuald', 'phone': '+22890000071', 'email': null, 'status': 'suspended', 'kyc_status': 'none',
    'currency_code': 'XOF', 'currency_decimals': 0, 'balance': 12500, 'created_at': '2026-10-01T10:00:00Z',
    'last_login_at': null, 'bet_count': 12, 'total_staked': 4200, 'total_won': 900, 'total_deposited': 20000,
    'total_withdrawn': 0});
}

final _help = HelpCenter.fromJson({
  'faq': [
    {'id': 1, 'category': 'deposit', 'question': 'Comment déposer de l\'argent ?', 'answer': 'Touchez DÉPOSER.'},
    {'id': 2, 'category': 'games', 'question': 'Comment fonctionne le Lonato ?', 'answer': '5 numéros parmi 01 à 90.'},
  ],
  'contact': {'whatsapp_url': null, 'hours': 'Tous les jours, 8 h – 22 h'},
});

Future<void> _show(WidgetTester tester, Widget screen, {FakeSupport? support, FakeAdmin? admin}) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      supportRepositoryProvider.overrideWithValue(support ?? FakeSupport()),
      adminRepositoryProvider.overrideWithValue(admin ?? FakeAdmin()),
      helpProvider.overrideWith((_) async => _help),
      myTicketsProvider.overrideWith((_) async => [Ticket.fromJson(_ticket('1', 'Retrait en attente', 'answered', 1))]),
    ],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('aide : demandes, horaires et recherche dans les questions fréquentes', (tester) async {
    await _show(tester, const Scaffold(body: HelpScreen()));
    expect(find.text('Retrait en attente'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'pastille : une réponse non lue');
    expect(find.textContaining('8 h – 22 h'), findsOneWidget);
    expect(find.text('Comment déposer de l\'argent ?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'lonato');
    await tester.pump();
    expect(find.text('Comment déposer de l\'argent ?'), findsNothing);
    expect(find.text('Comment fonctionne le Lonato ?'), findsOneWidget);
    await tester.tap(find.text('Comment fonctionne le Lonato ?'));
    await tester.pumpAndSettle();
    expect(find.text('5 numéros parmi 01 à 90.'), findsOneWidget);
  });

  testWidgets('nouvelle demande : formulaire vide refusé', (tester) async {
    await _show(tester, const NewTicketScreen());
    await tester.tap(find.text('ENVOYER'));
    await tester.pump();
    expect(find.text('Choisissez une catégorie'), findsOneWidget);
    expect(find.text('Au moins 3 caractères'), findsOneWidget);
    expect(find.text('Écrivez votre message'), findsOneWidget);
  });

  testWidgets('nouvelle demande depuis un retrait : catégorie et référence remplies', (tester) async {
    await _show(tester, const NewTicketScreen(category: 'withdrawal', reference: 'WDR-20261008-000001'));
    expect(find.text('Retrait'), findsOneWidget);
    expect(find.text('WDR-20261008-000001'), findsOneWidget);
  });

  testWidgets('conversation côté joueur : messages et réponse', (tester) async {
    final support = FakeSupport();
    await _show(tester, const TicketScreen(id: '1'), support: support);
    expect(find.textContaining('Vous ·'), findsOneWidget);
    expect(find.textContaining('Support · Yao'), findsOneWidget);
    expect(find.text('Le paiement part aujourd\'hui.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Merci !');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(support.replies, ['Merci !']);
    expect(find.text('Merci !'), findsOneWidget);
  });

  testWidgets('file du support et résolution d\'une demande', (tester) async {
    final admin = FakeAdmin();
    await _show(tester, const AdminSupportScreen(), admin: admin);
    expect(find.textContaining('Hubert Agbo · 6250398825'), findsOneWidget);
    expect(find.textContaining('À traiter'), findsWidgets);

    await _show(tester, const AdminTicketScreen(id: '1'), admin: admin);
    expect(find.text('Hubert Agbo · 6250398825'), findsOneWidget, reason: 'lien vers la fiche client');
    await tester.tap(find.byTooltip('Statut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marquer résolue'));
    await tester.pumpAndSettle();
    expect(admin.statuses, [TicketStatus.resolved]);
  });

  testWidgets('alertes anti-fraude et fiche client', (tester) async {
    await _show(tester, const AdminRiskScreen());
    expect(find.textContaining('Numéro de paiement d\'un autre compte'), findsOneWidget);
    expect(find.textContaining('6000000002'), findsOneWidget);
    expect(find.text('Clore'), findsOneWidget);

    await _show(tester, const AdminUsersScreen(initialId: '6000000001'));
    expect(find.text('Gédéon Romuald'), findsOneWidget);
    expect(find.text('Suspendu'), findsOneWidget);
    expect(find.text('Réactiver'), findsOneWidget, reason: 'compte suspendu : réactivation proposée');
  });
}
