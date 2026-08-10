import '../models/incident_model.dart';
import 'api_client.dart';

class IncidentService {
  IncidentService(this._client);

  final ApiClient _client;

  Future<IncidentModel> create({
    required String touristId,
    required String typeId,
    required int battery,
    required String description,
    required double lat,
    required double lng,
  }) async {
    final data = await _client.post(
      '/incidents',
      authenticated: true,
      body: {
        'tourist_id': touristId,
        'type_id': typeId,
        'battery': battery,
        'description': description,
        'lat': lat,
        'lng': lng,
      },
    ) as Map<String, dynamic>;
    return IncidentModel.fromJson(data);
  }

  Future<List<IncidentModel>> list() async {
    final data = await _client.get('/incidents') as dynamic;
    final values = data is List
        ? data
        : (data as Map<String, dynamic>)['items'] ??
              (data)['incidents'] ??
              const <dynamic>[];
    return (values as List)
        .whereType<Map<String, dynamic>>()
        .map(IncidentModel.fromJson)
        .toList();
  }

  Future<void> arrive(String incidentId) async {
    await _client.put('/incidents/$incidentId/arrive');
  }

  Future<void> resolve(String incidentId) async {
    await _client.put('/incidents/$incidentId/resolve');
  }

  Future<void> updateRrtStatus(String rrtId, String status) async {
    await _client.put('/rrt/$rrtId/status', body: {'status': status});
  }

  Future<void> updateLocation({
    required String incidentId,
    required double lat,
    required double lng,
    int? battery,
  }) async {
    await _client.put(
      '/incidents/$incidentId/location',
      body: {
        'lat': lat,
        'lng': lng,
        'battery': ?battery,
      },
    );
  }

  Future<void> updateRrtLocation({
    required String rrtId,
    required double lat,
    required double lng,
  }) async {
    await _client.put(
      '/rrt/$rrtId/location',
      body: {
        'lat': lat,
        'lng': lng,
      },
    );
  }
}
