import 'dart:math';

import 'package:geolocator/geolocator.dart';

class DeviceLocation {
  final double lat;
  final double lng;

  const DeviceLocation({required this.lat, required this.lng});
}

class LocationService {
  bool _simulationEnabled = false;
  int _simStep = 0;
  static const _simBase = DeviceLocation(lat: 12.9236, lng: 100.8824);

  bool get isSimulationEnabled => _simulationEnabled;

  void setSimulation(bool enabled) {
    _simulationEnabled = enabled;
    _simStep = 0;
  }

  Future<DeviceLocation> getCurrent() async {
    if (_simulationEnabled) {
      _simStep++;
      final angle = (_simStep % 360) * pi / 180;
      final radius = 0.004;
      return DeviceLocation(
        lat: _simBase.lat + radius * cos(angle),
        lng: _simBase.lng + radius * sin(angle),
      );
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission was not granted.');
    }
    final position = await Geolocator.getCurrentPosition();
    return DeviceLocation(lat: position.latitude, lng: position.longitude);
  }
}
