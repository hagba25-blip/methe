import '../models/dashboard.dart';
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
}
