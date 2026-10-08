import '../models/public_settings.dart';
import '../models/wallet.dart';
import '../services/api_client.dart';

class WalletRepository {
  WalletRepository(this._api);
  final ApiClient _api;

  Future<TransactionPage> transactions({TxFilter filter = TxFilter.all, int? cursor, int limit = 20}) async {
    final query = <String, String>{
      'limit': '$limit',
      if (cursor != null) 'cursor': '$cursor',
      if (filter.apiValue != null) 'kind': filter.apiValue!,
    };
    final qs = Uri(queryParameters: query).query;
    return TransactionPage.fromJson(await _api.get('/v1/wallet/transactions?$qs'));
  }

  Future<PublicSettings> publicSettings() async => PublicSettings.fromJson(await _api.get('/v1/settings/public'));
}
