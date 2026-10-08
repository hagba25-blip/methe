import '../models/dashboard.dart';
import '../models/risk.dart';
import '../services/api_client.dart';

class AdminRepository {
  AdminRepository(this._api);
  final ApiClient _api;

  Future<Dashboard> dashboard(DashboardPeriod period) async =>
      Dashboard.fromJson(await _api.get('/v1/admin/dashboard?period=${period.api}'));

  Future<List<AdminAction>> actions({int? before, int limit = 30}) async => [
        for (final a in await _api.getList('/v1/admin/actions?limit=$limit${before != null ? '&before=$before' : ''}'))
          AdminAction.fromJson(a as Map<String, dynamic>)
      ];

  /// [state] : open | resolved | all.
  Future<List<RiskEvent>> riskEvents({String state = 'open', String? clientId, int? before, int limit = 50}) async {
    final qs = Uri(queryParameters: {
      'state': state,
      'limit': '$limit',
      if (clientId != null) 'client_id': clientId,
      if (before != null) 'before': '$before',
    }).query;
    return [for (final e in await _api.getList('/v1/admin/risk-events?$qs')) RiskEvent.fromJson(e as Map<String, dynamic>)];
  }

  Future<RiskEvent> resolveRisk(int id, String note) async =>
      RiskEvent.fromJson(await _api.post('/v1/admin/risk-events/$id/resolve', {'note': note}));

  /// Fiche client (la consultation est tracée dans le journal des actions).
  Future<AdminUser> user(String publicId) async => AdminUser.fromJson(await _api.get('/v1/admin/users/$publicId'));

  Future<AdminUser> setStatus(String publicId, AccountStatus status, String reason) async => AdminUser.fromJson(
      await _api.post('/v1/admin/users/$publicId/status', {'status': status.name, 'reason': reason}));
}
