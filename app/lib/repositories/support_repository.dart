import '../models/support.dart';
import '../services/api_client.dart';

/// Côté joueur : aide, questions fréquentes et demandes au support.
class SupportRepository {
  SupportRepository(this._api);
  final ApiClient _api;

  Future<HelpCenter> help({String language = 'fr'}) async =>
      HelpCenter.fromJson(await _api.get('/v1/support/help?language=$language'));

  Future<List<Ticket>> myTickets() async =>
      [for (final t in await _api.getList('/v1/support/tickets')) Ticket.fromJson(t as Map<String, dynamic>)];

  Future<Ticket> open({
    required TicketCategory category,
    required String subject,
    required String message,
    String? relatedReference,
  }) async =>
      Ticket.fromJson(await _api.post('/v1/support/tickets', {
        'category': category.name,
        'subject': subject,
        'message': message,
        if (relatedReference != null && relatedReference.trim().isNotEmpty) 'related_reference': relatedReference.trim(),
      }));

  Future<Ticket> ticket(String id) async => Ticket.fromJson(await _api.get('/v1/support/tickets/$id'));

  Future<Ticket> reply(String id, String body) async =>
      Ticket.fromJson(await _api.post('/v1/support/tickets/$id/messages', {'body': body}));

  Future<Ticket> close(String id) async => Ticket.fromJson(await _api.post('/v1/support/tickets/$id/close', {}));
}
