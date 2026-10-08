import '../models/withdrawal.dart';
import '../services/api_client.dart';

class WithdrawalRepository {
  WithdrawalRepository(this._api);
  final ApiClient _api;

  Future<WithdrawalInfo> info() async => WithdrawalInfo.fromJson(await _api.get('/v1/withdrawals/info'));

  /// [requestKey] reste identique si l'utilisateur renvoie le même formulaire :
  /// le serveur ne bloque le montant qu'une seule fois.
  Future<Withdrawal> request(int amount, WithdrawalMethod method, String account, String requestKey) async =>
      Withdrawal.fromJson(await _api.post(
          '/v1/withdrawals', {'amount': amount, 'method': method.api, 'payout_account': account},
          idempotencyKey: requestKey));

  Future<List<Withdrawal>> mine() async =>
      [for (final w in await _api.getList('/v1/withdrawals')) Withdrawal.fromJson(w as Map<String, dynamic>)];

  Future<Withdrawal> cancel(String id) async => Withdrawal.fromJson(await _api.post('/v1/withdrawals/$id/cancel', {}));

  // --- Administration -------------------------------------------------------
  Future<List<Withdrawal>> adminList({WithdrawalStatus status = WithdrawalStatus.pending}) async => [
        for (final w in await _api.getList('/v1/admin/withdrawals?status=${status.api}'))
          Withdrawal.fromJson(w as Map<String, dynamic>)
      ];

  /// [action] : review | approve | pay | reject (motif obligatoire pour reject).
  Future<Withdrawal> process(String id, String action, {String? reason}) async => Withdrawal.fromJson(
      await _api.post('/v1/admin/withdrawals/$id/$action', {if (reason != null) 'reason': reason}));
}
