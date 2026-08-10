class IncidentCoords {
  final double lat;
  final double lng;

  IncidentCoords({required this.lat, required this.lng});

  factory IncidentCoords.fromJson(Map<String, dynamic> json) {
    return IncidentCoords(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
    };
  }
}

class IncidentModel {
  final String id;
  final int? number;
  final String touristId;
  final String? rrtId;
  final String? dispatcherId;
  final String? sectorId;
  final String status; // 'created', 'en_route', 'rrt_arrived', 'incident_resolved'
  final int battery;
  final String description;
  final IncidentCoords coords;
  final String createdAt;
  final String? touristName;
  final String? touristPhone;
  final String? typeName;

  IncidentModel({
    required this.id,
    this.number,
    required this.touristId,
    this.rrtId,
    this.dispatcherId,
    this.sectorId,
    required this.status,
    required this.battery,
    required this.description,
    required this.coords,
    required this.createdAt,
    this.touristName,
    this.touristPhone,
    this.typeName,
  });

  factory IncidentModel.fromJson(Map<String, dynamic> json) {
    IncidentCoords coordsObj;
    if (json['coords'] is Map<String, dynamic>) {
      coordsObj = IncidentCoords.fromJson(json['coords']);
    } else {
      coordsObj = IncidentCoords(
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      );
    }

    String? tName;
    String? tPhone;
    if (json['tourist'] is Map<String, dynamic>) {
      tName = json['tourist']['full_name'] ?? json['tourist']['name'];
      tPhone = json['tourist']['phone'];
    }

    String? typeN;
    if (json['type'] is Map<String, dynamic>) {
      typeN = json['type']['name'] ?? json['type']['title'];
    } else if (json['type_name'] is String) {
      typeN = json['type_name'];
    }

    return IncidentModel(
      id: json['id'] ?? '',
      number: json['number'] as int?,
      touristId: json['tourist_id'] ?? '',
      rrtId: json['rrt_id'],
      dispatcherId: json['dispatcher_id'],
      sectorId: json['sector_id'],
      status: json['status'] ?? 'created',
      battery: json['battery'] is int ? json['battery'] : 100,
      description: json['description'] ?? '',
      coords: coordsObj,
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
      touristName: tName,
      touristPhone: tPhone,
      typeName: typeN,
    );
  }
}
