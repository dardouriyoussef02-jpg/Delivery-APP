import '../models/fleet_stats.dart';
import 'api_client.dart';

/// Fetches the admin dashboard numbers (`GET /api/v1/stats`).
///
/// Authorization happens on the server: a non-admin session gets a 403 which
/// surfaces here as a normal [ApiException] the screen can display.
class StatsRepository {
  StatsRepository(this._api);

  final ApiClient _api;

  Future<FleetStats> fetch() async {
    final data = await _api.get('/api/v1/stats');
    if (data is! Map) {
      throw ApiException('The server returned an unexpected stats payload.');
    }
    return FleetStats.fromJson(data.cast<String, dynamic>());
  }
}
