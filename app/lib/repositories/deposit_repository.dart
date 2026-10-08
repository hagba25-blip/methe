import 'dart:math';

import '../models/deposit.dart';
import '../services/api_client.dart';

class DepositRepository {
  DepositRepository(this._api);
  final ApiClient _api;

  Future<List<Agent>> agents() async =>
      [for (final a in await _api.getList('/v1/agents')) Agent.fromJson(a as Map<String, dynamic>)];

  Future<DepositCreated> request(String agentId, int amount) async =>
      DepositCreated.fromJson(await _api.post('/v1/deposits', {'agent_id': agentId, 'amount': amount}));

  Future<List<Deposit>> mine() async =>
      [for (final d in await _api.getList('/v1/deposits')) Deposit.fromJson(d as Map<String, dynamic>)];

  Future<void> cancel(String id) => _api.post('/v1/deposits/$id/cancel', {});

  // --- Administration -------------------------------------------------------
  Future<List<Deposit>> adminList({String status = 'pending'}) async => [
        for (final d in await _api.getList('/v1/admin/deposits?status=$status'))
          Deposit.fromJson(d as Map<String, dynamic>)
      ];

  Future<BalanceChange> approve(String id, {int? amount, String? note}) async => BalanceChange.fromJson(
      await _api.post('/v1/admin/deposits/$id/approve', {if (amount != null) 'amount': amount, if (note != null) 'note': note}));

  Future<void> reject(String id, String reason) => _api.post('/v1/admin/deposits/$id/reject', {'reason': reason});

  /// [requestKey] doit rester identique si l'admin re-clique : un seul crédit sera passé.
  Future<BalanceChange> credit(String publicId, int amount, String reason, String requestKey) async =>
      BalanceChange.fromJson(await _api.post('/v1/admin/users/$publicId/credit', {'amount': amount, 'reason': reason},
          idempotencyKey: requestKey));

  static String newRequestKey() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
