import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/incident_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/app_state.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/presentation/widgets/slide_sos_button.dart';
import '../../home/presentation/widgets/subscription_card.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.auth,
    required this.incidents,
    required this.location,
    required this.realtime,
    required this.storage,
    required this.onSignedOut,
  });

  final AuthService auth;
  final IncidentService incidents;
  final LocationService location;
  final RealtimeService realtime;
  final AppStateStorage storage;
  final VoidCallback onSignedOut;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  UserModel? _user;
  int _index = 0;
  bool _loadingProfile = true;
  List<IncidentModel> _items = const [];
  String _rrtStatus = 'ready';
  final Set<String> _acknowledged = {};
  final Map<String, String> _seenStatuses = {};
  String? _liveResolvedId;
  DeviceLocation? _position;
  Timer? _positionTimer;
  Timer? _touristLocationTimer;
  Timer? _rrtLocationTimer;
  Timer? _incidentPollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _touristLocationTimer?.cancel();
    _rrtLocationTimer?.cancel();
    _incidentPollTimer?.cancel();
    widget.realtime.disconnect();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _user = await widget.auth.loadProfile();
    } on ApiException {
      _user = await widget.auth.storedUser();
    }
    if (_user == null) {
      await widget.auth.logout();
      widget.onSignedOut();
      return;
    }
    await _loadIncidents();
    await widget.realtime.connect(onEvent: (type, _) {
      if (type == 'INCIDENT_UPDATE') _loadIncidents();
    });
    _syncTouristLocationUpdates();
    _syncRrtLocationUpdates();
    _syncPosition();
    if (mounted) setState(() => _loadingProfile = false);
  }

  void _syncPosition() {
    if (_user?.role != 'tourist') return;
    _positionTimer?.cancel();
    _fetchPosition();
    _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchPosition());
  }

  bool _fetchingPosition = false;

  Future<void> _fetchPosition() async {
    if (_fetchingPosition) return;
    _fetchingPosition = true;
    try {
      final position = await widget.location.getCurrent();
      if (!mounted) return;
      final current = _position;
      if (current == null ||
          current.lat != position.lat ||
          current.lng != position.lng) {
        setState(() => _position = position);
      }
    } on Exception {
      // Position will be retried by the timer.
    } finally {
      _fetchingPosition = false;
    }
  }

  Future<void> _loadIncidents() async {
    try {
      final incidents = await widget.incidents.list();
      if (mounted) {
        setState(() {
          _items = incidents;
          _trackIncidentStatuses(incidents);
        });
        _syncTouristLocationUpdates();
      }
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    }
  }

  bool _isResolvedStatus(String status) =>
      status == 'resolved' || status == 'incident_resolved';

  void _trackIncidentStatuses(List<IncidentModel> incidents) {
    if (_liveResolvedId != null) {
      IncidentModel? live;
      for (final incident in incidents) {
        if (incident.id == _liveResolvedId) live = incident;
      }
      if (live == null || !_isResolvedStatus(live.status)) _liveResolvedId = null;
    }
    for (final incident in incidents) {
      final previous = _seenStatuses[incident.id];
      if (previous != null &&
          !_isResolvedStatus(previous) &&
          _isResolvedStatus(incident.status)) {
        _liveResolvedId = incident.id;
      }
      _seenStatuses[incident.id] = incident.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user!.role == 'rrt') {
      return _RrtShell(
        user: _user!,
        incidents: _assignedIncidents,
        rrtStatus: _rrtStatus,
        location: widget.location,
        storage: widget.storage,
        onStatusChanged: _setRrtStatus,
        onArrival: _arrive,
        onResolve: _resolve,
        onRefresh: _loadIncidents,
        onSignOut: _signOut,
      );
    }
    final active = _activeTouristIncident;
    final body = _index == 2
        ? _ProfilePage(user: _user!, storage: widget.storage, location: widget.location, onSignOut: _signOut)
        : _SosTab(
            incident: active,
            position: _position,
            onDispatch: _dispatchSos,
            onAcknowledge: _acknowledgeIncident,
            onMessage: _message,
          );
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: _GuardianBottomNav(
        currentIndex: _index,
        incident: active,
        onSelect: (value) => setState(() => _index = value),
      ),
    );
  }

  List<IncidentModel> get _assignedIncidents => _items
      .where((incident) =>
          incident.rrtId == _user!.id &&
          incident.status != 'resolved' &&
          incident.status != 'incident_resolved')
      .toList();

  IncidentModel? get _activeTouristIncident {
    if (_user?.role != 'tourist') return null;
    for (final incident in _items) {
      if (incident.touristId != _user!.id) continue;
      if (_acknowledged.contains(incident.id)) continue;
      if (_isResolvedStatus(incident.status)) {
        if (incident.id == _liveResolvedId) return incident;
        continue;
      }
      return incident;
    }
    return null;
  }

  Future<void> _dispatchSos() async {
    final type = await _chooseIncidentType();
    if (type == null) return;
    try {
      final location = await widget.location.getCurrent();
      final battery = await Battery().batteryLevel;
      final incident = await widget.incidents.create(
        touristId: _user!.id,
        typeId: type.id,
        battery: battery,
        description: type.description,
        lat: location.lat,
        lng: location.lng,
      );
      await _loadIncidents();
      if (mounted) {
        setState(() => _index = 0);
        _message('SOS call #${incident.number ?? ''} received. Security is on the way.');
      }
    } on ApiException catch (error) {
      _message(error.message);
    } on Exception catch (error) {
      _message(error.toString());
    }
  }

  void _acknowledgeIncident(String id) {
    setState(() {
      _acknowledged.add(id);
      if (_liveResolvedId == id) _liveResolvedId = null;
    });
  }

  void _syncTouristLocationUpdates() {
    _touristLocationTimer?.cancel();
    _incidentPollTimer?.cancel();
    if (_activeTouristIncident == null) return;
    _sendTouristLocation();
    _touristLocationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sendTouristLocation();
    });
    _incidentPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadIncidents();
    });
  }

  bool _sendingLocation = false;

  Future<void> _sendTouristLocation() async {
    if (_sendingLocation) return;
    _sendingLocation = true;
    final incident = _activeTouristIncident;
    if (incident == null || _user == null) {
      _sendingLocation = false;
      return;
    }
    try {
      final location = await widget.location.getCurrent();
      final battery = await Battery().batteryLevel;
      await widget.incidents.updateLocation(
        incidentId: incident.id,
        lat: location.lat,
        lng: location.lng,
        battery: battery,
      );
    } on Exception {
      // The active incident remains visible if a later location update fails.
    } finally {
      _sendingLocation = false;
    }
  }

  void _syncRrtLocationUpdates() {
    if (_user?.role != 'rrt') return;
    _rrtLocationTimer?.cancel();
    _sendRrtLocation();
    _rrtLocationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sendRrtLocation();
    });
  }

  Future<void> _sendRrtLocation() async {
    if (_user == null || _user!.role != 'rrt') return;
    try {
      final location = await widget.location.getCurrent();
      await widget.incidents.updateRrtLocation(
        rrtId: _user!.id,
        lat: location.lat,
        lng: location.lng,
      );
    } on Exception {
      // A later update will retry.
    }
  }

  Future<_IncidentType?> _chooseIncidentType() {
    final description = TextEditingController();
    var selected = _incidentTypes.first;
    return showModalBottomSheet<_IncidentType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Dispatch SOS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Select the type of emergency.', style: TextStyle(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 12),
              RadioGroup<_IncidentType>(
                groupValue: selected,
                onChanged: (value) => setModalState(() => selected = value!),
                child: Column(
                  children: _incidentTypes.map((type) => RadioListTile<_IncidentType>(
                    value: type,
                    title: Text(type.title),
                    secondary: Icon(type.icon, color: type.color),
                    activeColor: AppColors.primary,
                  )).toList(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'Describe the emergency')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected.copyWith(
                  description: description.text.trim().isEmpty ? selected.title : description.text.trim(),
                )),
                child: const Text('Send SOS'),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(description.dispose);
  }

  Future<void> _arrive(IncidentModel incident) async {
    try {
      await widget.incidents.arrive(incident.id);
      await _loadIncidents();
    } on ApiException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _resolve(IncidentModel incident) async {
    try {
      await widget.incidents.resolve(incident.id);
      await _loadIncidents();
    } on ApiException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _setRrtStatus(String status) async {
    try {
      await widget.incidents.updateRrtStatus(_user!.id, status);
      if (mounted) setState(() => _rrtStatus = status);
    } on ApiException catch (error) {
      _message(error.message);
    } on Exception catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _signOut() async {
    await widget.auth.logout();
    widget.onSignedOut();
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

// ============================================================
//  Нижняя навигация туриста: Map · SOS (центр) · Profile
// ============================================================

class _GuardianBottomNav extends StatelessWidget {
  const _GuardianBottomNav({
    required this.currentIndex,
    required this.incident,
    required this.onSelect,
  });

  final int currentIndex;
  final IncidentModel? incident;
  final ValueChanged<int> onSelect;

  Color get _sosColor {
    if (incident == null) return AppColors.primary;
    return switch (incident!.status) {
      'arrived' || 'rrt_arrived' || 'resolved' || 'incident_resolved' => AppColors.secondary,
      _ => AppColors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: AppColors.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(children: [
            _navItem(Icons.map_outlined, Icons.map, 'Map', 0),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -18),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: _sosColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surfaceContainerLowest, width: 4),
                        boxShadow: const [
                          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
                        ],
                      ),
                      child: const Center(
                        child: Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _navItem(Icons.person_outline, Icons.person, 'Profile', 2),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, IconData selectedIcon, String label, int index) {
    final selected = currentIndex == index;
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(index),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(selected ? selectedIcon : icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
        ]),
      ),
    );
  }
}

// ============================================================
//  Вкладка SOS: активация / поиск / в пути / прибыл / завершён
// ============================================================

class _SosTab extends StatelessWidget {
  const _SosTab({
    required this.incident,
    required this.position,
    required this.onDispatch,
    required this.onAcknowledge,
    required this.onMessage,
  });

  final IncidentModel? incident;
  final DeviceLocation? position;
  final Future<void> Function() onDispatch;
  final void Function(String id) onAcknowledge;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    final current = incident;
    if (current == null) {
      return _SosActivationScreen(position: position, onDispatch: onDispatch);
    }
    return switch (current.status) {
      'in_progress' || 'en_route' => _TrackingScreen(incident: current, position: position),
      'arrived' || 'rrt_arrived' => _ArrivedScreen(incident: current, position: position),
      'resolved' || 'incident_resolved' => _ResolvedScreen(incident: current, position: position, onAcknowledge: onAcknowledge, onMessage: onMessage),
      _ => _SearchingScreen(incident: current, position: position),
    };
  }
}

class _SosActivationScreen extends StatelessWidget {
  const _SosActivationScreen({required this.position, required this.onDispatch});

  final DeviceLocation? position;
  final Future<void> Function() onDispatch;

  @override
  Widget build(BuildContext context) {
    final center = position == null
        ? const LatLng(12.9255, 100.8729)
        : LatLng(position!.lat, position!.lng);
    final markers = <Marker>[
      if (position != null)
        Marker(
          point: LatLng(position!.lat, position!.lng),
          width: 46,
          height: 72,
          child: _UserMarker(),
        ),
    ];
    return Stack(children: [
      _LightMapBackground(center: center, markers: markers),
      SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
              _TopSosButton(label: 'TEST\nSOS'),
              _TopSosButton(icon: Icons.schedule_outlined, label: 'SOS'),
            ]),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: SlideSosButton(onDispatch: onDispatch),
          ),
        ]),
      ),
    ]);
  }
}

class _TopSosButton extends StatelessWidget {
  const _TopSosButton({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.sosDark,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(height: 1),
          ],
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1.15),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  Поиск экипажа (created)
// ============================================================

class _SearchingScreen extends StatelessWidget {
  const _SearchingScreen({required this.incident, required this.position});

  final IncidentModel incident;
  final DeviceLocation? position;

  @override
  Widget build(BuildContext context) {
    final anchor = LatLng(incident.coords.lat, incident.coords.lng);
    final center = position == null
        ? anchor
        : LatLng(position!.lat, position!.lng);
    final markers = <Marker>[
      Marker(point: anchor, width: 150, height: 150, child: _PulsingSosMarker()),
    ];
    return Stack(children: [
      _LightMapBackground(center: center, markers: markers, interactive: false),
      Positioned(left: 16, right: 16, bottom: 16, child: _SearchingCard(incident: incident)),
    ]);
  }
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard({required this.incident});

  final IncidentModel incident;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(alignment: Alignment.center, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceContainerLow),
              child: const Icon(Icons.shield_outlined, color: AppColors.onSurface),
            ),
            const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error)),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('We are searching for a security crew for you.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.25)),
              const SizedBox(height: 4),
              const Text('It could take up to 1 minute.', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              const Text('WAIT TIME',
                  style: TextStyle(fontSize: 9, letterSpacing: 0.5, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              _ElapsedTimer(createdAt: incident.createdAt),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cancelling is not available yet.')),
          ),
          child: const Text('Cancel the order'),
        ),
      ]),
    );
  }
}

// ============================================================
//  Группа в пути (in_progress / en_route)
// ============================================================

class _TrackingScreen extends StatelessWidget {
  const _TrackingScreen({required this.incident, required this.position});

  final IncidentModel incident;
  final DeviceLocation? position;

  @override
  Widget build(BuildContext context) {
    final anchor = LatLng(incident.coords.lat, incident.coords.lng);
    final center = position == null
        ? anchor
        : LatLng(position!.lat, position!.lng);
    final markers = <Marker>[
      if (position != null)
        Marker(
          point: LatLng(position!.lat, position!.lng),
          width: 46,
          height: 72,
          child: _UserMarker(),
        ),
    ];
    return Stack(children: [
      _LightMapBackground(center: center, markers: markers, interactive: false),
      Positioned(left: 16, right: 16, bottom: 16, child: _TrackingCard(incident: incident)),
    ]);
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.incident});

  final IncidentModel incident;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.secondaryContainer,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.shield_outlined, color: AppColors.onSecondaryContainer, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('The crew is on your way.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.2)),
              const SizedBox(height: 4),
              const Text('Please keep your phone on so security can find you.',
                  style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        const Text('Comment:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Type important information',
            suffixIcon: Icon(Icons.edit_outlined, color: AppColors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message sent.')),
          ),
          child: const Text('Send'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cancelling is not available yet.')),
          ),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Cancel the order'),
        ),
      ]),
    );
  }
}

// ============================================================
//  Группа прибыла (arrived)
// ============================================================

class _ArrivedScreen extends StatelessWidget {
  const _ArrivedScreen({required this.incident, required this.position});

  final IncidentModel incident;
  final DeviceLocation? position;

  @override
  Widget build(BuildContext context) {
    final anchor = LatLng(incident.coords.lat, incident.coords.lng);
    final center = position == null
        ? anchor
        : LatLng(position!.lat, position!.lng);
    final markers = <Marker>[
      if (position != null)
        Marker(
          point: LatLng(position!.lat, position!.lng),
          width: 46,
          height: 72,
          child: _UserMarker(),
        ),
    ];
    return Stack(children: [
      _LightMapBackground(center: center, markers: markers, interactive: false),
      Positioned(left: 16, right: 16, bottom: 16, child: _ArrivedCard(incident: incident)),
    ]);
  }
}

class _ArrivedCard extends StatelessWidget {
  const _ArrivedCard({required this.incident});

  final IncidentModel incident;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('The crew has arrived.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
        const SizedBox(height: 6),
        const Text('Please stay where you are. Security is with you and will complete the call shortly.',
            style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant, height: 1.4)),
      ]),
    );
  }
}

// ============================================================
//  Вызов завершён (resolved)
// ============================================================

class _ResolvedScreen extends StatelessWidget {
  const _ResolvedScreen({
    required this.incident,
    required this.position,
    required this.onAcknowledge,
    required this.onMessage,
  });

  final IncidentModel incident;
  final DeviceLocation? position;
  final void Function(String id) onAcknowledge;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    final anchor = LatLng(incident.coords.lat, incident.coords.lng);
    final center = position == null
        ? anchor
        : LatLng(position!.lat, position!.lng);
    final markers = <Marker>[
      if (position != null)
        Marker(
          point: LatLng(position!.lat, position!.lng),
          width: 46,
          height: 72,
          child: _UserMarker(),
        ),
    ];
    return Stack(children: [
      _LightMapBackground(center: center, markers: markers),
      Positioned(left: 16, right: 16, bottom: 16, child: _ResolvedCard(incident: incident, onAcknowledge: onAcknowledge, onMessage: onMessage)),
    ]);
  }
}

class _ResolvedCard extends StatelessWidget {
  const _ResolvedCard({
    required this.incident,
    required this.onAcknowledge,
    required this.onMessage,
  });

  final IncidentModel incident;
  final void Function(String id) onAcknowledge;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.inverseSurface),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('The call has been completed.\nWe hope you are now safe!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.3)),
          ),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => onAcknowledge(incident.id),
          child: const Text('Thanks'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => onMessage('Contact support is not available yet.'),
          child: const Text('Contact support'),
        ),
      ]),
    );
  }
}

// ============================================================
//  Карта туриста (светлая)
// ============================================================

// ============================================================
//  Интерфейс экипажа RRT
// ============================================================

class _RrtShell extends StatefulWidget {
  const _RrtShell({
    required this.user,
    required this.incidents,
    required this.rrtStatus,
    required this.location,
    required this.storage,
    required this.onStatusChanged,
    required this.onArrival,
    required this.onResolve,
    required this.onRefresh,
    required this.onSignOut,
  });

  final UserModel user;
  final List<IncidentModel> incidents;
  final String rrtStatus;
  final LocationService location;
  final AppStateStorage storage;
  final Future<void> Function(String) onStatusChanged;
  final Future<void> Function(IncidentModel) onArrival;
  final Future<void> Function(IncidentModel) onResolve;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSignOut;

  @override
  State<_RrtShell> createState() => _RrtShellState();
}

class _RrtShellState extends State<_RrtShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _RrtMapPage(
        user: widget.user,
        incidents: widget.incidents,
        location: widget.location,
        rrtStatus: widget.rrtStatus,
        onArrival: widget.onArrival,
        onResolve: widget.onResolve,
      ),
      _RrtCallsPage(
        user: widget.user,
        items: widget.incidents,
        rrtStatus: widget.rrtStatus,
        onRefresh: widget.onRefresh,
        onArrival: widget.onArrival,
        onResolve: widget.onResolve,
        onStatusChanged: widget.onStatusChanged,
      ),
      _ProfilePage(user: widget.user, storage: widget.storage, location: widget.location, onSignOut: widget.onSignOut),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Calls'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _RrtMapPage extends StatefulWidget {
  const _RrtMapPage({
    required this.user,
    required this.incidents,
    required this.location,
    required this.rrtStatus,
    required this.onArrival,
    required this.onResolve,
  });

  final UserModel user;
  final List<IncidentModel> incidents;
  final LocationService location;
  final String rrtStatus;
  final Future<void> Function(IncidentModel) onArrival;
  final Future<void> Function(IncidentModel) onResolve;

  @override
  State<_RrtMapPage> createState() => _RrtMapPageState();
}

class _RrtMapPageState extends State<_RrtMapPage> {
  final MapController _mapController = MapController();
  DeviceLocation? _position;
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _updatePosition();
    _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) => _updatePosition());
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _updatePosition() async {
    try {
      final position = await widget.location.getCurrent();
      if (!mounted) return;
      setState(() {
        final firstFix = _position == null;
        _position = position;
        if (firstFix) {
          _mapController.move(LatLng(position.lat, position.lng), _mapController.camera.zoom);
        }
      });
    } on Exception {
      // Position will be retried by the timer.
    }
  }

  void _centerOnMe() {
    if (_position == null) return;
    _mapController.move(LatLng(_position!.lat, _position!.lng), _mapController.camera.zoom);
  }

  void _openIncident(IncidentModel incident) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('SOS #${incident.number ?? '---'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(incident.description.isEmpty ? 'Emergency request' : incident.description),
          const SizedBox(height: 8),
          Text(_incidentStatusText(incident.status), style: const TextStyle(color: AppColors.primary)),
          Text('${incident.coords.lat.toStringAsFixed(5)}, ${incident.coords.lng.toStringAsFixed(5)}', style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            if (incident.status != 'arrived' && incident.status != 'resolved' && incident.status != 'incident_resolved')
              OutlinedButton(onPressed: () { Navigator.pop(context); widget.onArrival(incident); }, child: const Text('Arrived')),
            if (incident.status != 'resolved' && incident.status != 'incident_resolved')
              FilledButton(onPressed: () { Navigator.pop(context); widget.onResolve(incident); }, child: const Text('Resolve')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _position == null
        ? const LatLng(12.9255, 100.8729)
        : LatLng(_position!.lat, _position!.lng);
    final markers = <Marker>[
      if (_position != null)
        Marker(
          point: LatLng(_position!.lat, _position!.lng),
          width: 44,
          height: 44,
          child: _shieldIcon(color: _rrtUnitColor(widget.rrtStatus), bolt: true),
        ),
      ...widget.incidents
          .where((incident) => incident.status != 'resolved' && incident.status != 'incident_resolved')
          .map((incident) => Marker(
                point: LatLng(incident.coords.lat, incident.coords.lng),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => _openIncident(incident),
                  child: _shieldIcon(color: _incidentColor(incident.status)),
                ),
              )),
    ];
    return Stack(children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 15,
          minZoom: 3,
          maxZoom: 16,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.rrtClient',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
      Positioned(
        top: 12,
        left: 12,
        right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            const Icon(Icons.person_pin_circle, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.user.fullName.isEmpty ? widget.user.phone : widget.user.fullName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${widget.incidents.where((i) => i.status != 'resolved' && i.status != 'incident_resolved').length} active calls', style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
          ]),
        ),
      ),
      if (_position == null)
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(16)),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Locating you...', style: TextStyle(color: AppColors.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      Positioned(
        right: 16,
        bottom: 24,
        child: FloatingActionButton(
          heroTag: 'rrt_center',
          onPressed: _centerOnMe,
          backgroundColor: AppColors.surfaceContainerLowest,
          foregroundColor: AppColors.primary,
          shape: const CircleBorder(),
          child: const Icon(Icons.my_location),
        ),
      ),
    ]);
  }
}

class _RrtCallsPage extends StatelessWidget {
  const _RrtCallsPage({required this.user, required this.items, required this.rrtStatus, required this.onRefresh, required this.onArrival, required this.onResolve, required this.onStatusChanged});
  final UserModel user;
  final List<IncidentModel> items;
  final String rrtStatus;
  final Future<void> Function() onRefresh;
  final Future<void> Function(IncidentModel) onArrival;
  final Future<void> Function(IncidentModel) onResolve;
  final Future<void> Function(String) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          const Text('My calls', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: rrtStatus,
            decoration: const InputDecoration(labelText: 'Crew status'),
            items: const ['ready', 'en_route', 'arrived', 'busy', 'offline'].map((status) => DropdownMenuItem(value: status, child: Text(status.replaceAll('_', ' ').toUpperCase()))).toList(),
            onChanged: (value) { if (value != null) onStatusChanged(value); },
          ),
          const SizedBox(height: 12),
          if (items.isEmpty) const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('No assigned calls yet.', style: TextStyle(color: AppColors.onSurfaceVariant))),
          ),
          ...items.map((incident) => _IncidentCard(incident: incident, isRrt: true, onArrival: onArrival, onResolve: onResolve)),
        ],
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, required this.isRrt, required this.onArrival, required this.onResolve});
  final IncidentModel incident;
  final bool isRrt;
  final Future<void> Function(IncidentModel) onArrival;
  final Future<void> Function(IncidentModel) onResolve;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SOS #${incident.number ?? '---'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(incident.description.isEmpty ? 'Emergency request' : incident.description),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_incidentStatusText(incident.status), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          Text('Coordinates: ${incident.coords.lat.toStringAsFixed(5)}, ${incident.coords.lng.toStringAsFixed(5)}', style: const TextStyle(color: AppColors.onSurfaceVariant)),
          if (isRrt) Wrap(spacing: 8, children: [
            if (incident.status != 'rrt_arrived' && incident.status != 'incident_resolved') OutlinedButton(onPressed: () => onArrival(incident), child: const Text('Arrived')),
            if (incident.status != 'incident_resolved') FilledButton(onPressed: () => onResolve(incident), child: const Text('Resolve')),
          ]),
        ]),
      ),
    );
  }
}

// ============================================================
//  Профиль
// ============================================================

class _ProfilePage extends StatefulWidget {
  const _ProfilePage({required this.user, required this.storage, required this.location, required this.onSignOut});
  final UserModel user;
  final AppStateStorage storage;
  final LocationService location;
  final Future<void> Function() onSignOut;

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  bool _simulateGps = false;

  @override
  void initState() {
    super.initState();
    _simulateGps = widget.location.isSimulationEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 16),
      const Text('Profile', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 24),
      ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(widget.user.fullName.isEmpty ? 'User' : widget.user.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(widget.user.phone),
        tileColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      const SizedBox(height: 12),
      ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: const Text('Role'),
        subtitle: Text(widget.user.role.toUpperCase()),
        tileColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      const SizedBox(height: 12),
      ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: const Text('Server URL'),
        subtitle: FutureBuilder<String>(future: widget.storage.getBaseUrl(), builder: (_, snap) => Text(snap.data ?? '')),
        tileColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      const SizedBox(height: 16),
      SubscriptionCard(validUntil: 'Oct 24, 2026', onTap: () {}),
      const SizedBox(height: 16),
      SwitchListTile(
        secondary: const Icon(Icons.gps_fixed),
        title: const Text('Simulate GPS'),
        subtitle: const Text('Test: coordinates drive in a circle without moving'),
        value: _simulateGps,
        onChanged: (value) {
          setState(() => _simulateGps = value);
          widget.location.setSimulation(value);
        },
        tileColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      const Divider(height: 32),
      ListTile(
        leading: const Icon(Icons.logout, color: AppColors.primary),
        title: const Text('Sign out'),
        onTap: widget.onSignOut,
      ),
    ]);
  }
}

// ============================================================
//  Общие помощники
// ============================================================

String _incidentStatusText(String status) => switch (status) {
  'created' => 'Searching for crew',
  'en_route' || 'in_progress' => 'Crew on the way',
  'arrived' || 'rrt_arrived' => 'Crew arrived',
  'resolved' || 'incident_resolved' => 'Completed',
  _ => 'Status: ${status.replaceAll('_', ' ')}',
};

Color _incidentColor(String status) => switch (status) {
  'in_progress' || 'en_route' || 'arrived' => const Color(0xFFFFB703),
  'resolved' || 'incident_resolved' => AppColors.secondary,
  _ => AppColors.error,
};

Color _rrtUnitColor(String status) => switch (status) {
  'en_route' || 'arrived' || 'busy' => const Color(0xFF3B82F6),
  'offline' => const Color(0xFF6B7280),
  _ => AppColors.secondary,
};

Widget _shieldIcon({required Color color, bool bolt = false}) {
  final inner = bolt
      ? '<path d="M13 7l-3 4.5h3L11 16l4-5h-3l2-4z" fill="#ffffff" stroke="none"/>'
      : '<circle cx="12" cy="11" r="2.5" fill="#ffffff"/>';
  final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  final svg =
      '<svg width="34" height="34" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" fill="$hex" stroke="#ffffff" stroke-width="1.5"/>'
      '$inner</svg>';
  return SvgPicture.string(svg, width: 34, height: 34);
}

// ============================================================
//  Маркеры и фон
// ============================================================

class _LightMapBackground extends StatefulWidget {
  const _LightMapBackground({
    required this.center,
    this.markers = const [],
    this.interactive = true,
  });

  final LatLng center;
  final List<Marker> markers;
  final bool interactive;

  @override
  State<_LightMapBackground> createState() => _LightMapBackgroundState();
}

class _LightMapBackgroundState extends State<_LightMapBackground> {
  final MapController _controller = MapController();
  bool _hasCentered = false;

  @override
  void didUpdateWidget(_LightMapBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasCentered) return;
    if (oldWidget.center.latitude != widget.center.latitude ||
        oldWidget.center.longitude != widget.center.longitude) {
      _controller.move(widget.center, _controller.camera.zoom);
      _hasCentered = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceContainerLowest,
      child: FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: widget.center,
          initialZoom: 15,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.rrtClient',
          ),
          if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
        ],
      ),
    );
  }
}

class _PulsingSosMarker extends StatefulWidget {
  const _PulsingSosMarker();

  @override
  State<_PulsingSosMarker> createState() => _PulsingSosMarkerState();
}

class _PulsingSosMarkerState extends State<_PulsingSosMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const avatar = 46.0;
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(children: [
        Positioned(
          left: 52,
          top: 52,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final size = avatar + 60 * t;
              final shift = (size - avatar) / 2;
              return Transform.translate(
                offset: Offset(-shift, -shift),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: (1 - t) * 0.6),
                      width: 3,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 52,
          top: 52,
          child: Container(
            width: avatar,
            height: avatar,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceContainerLowest,
              border: Border.all(color: AppColors.error, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: const Icon(Icons.person, color: AppColors.onSurfaceVariant, size: 24),
          ),
        ),
        Positioned(
          top: 22,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.all(Radius.circular(4))),
              child: Text('SOS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _UserMarker extends StatelessWidget {
  const _UserMarker();

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(3)),
        child: const Text('ME', style: TextStyle(fontSize: 8, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      const SizedBox(height: 4),
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.primary, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: const Icon(Icons.person, color: AppColors.primary, size: 22),
      ),
    ]);
  }
}

class _ElapsedTimer extends StatefulWidget {
  const _ElapsedTimer({required this.createdAt});

  final String createdAt;

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    final created = DateTime.tryParse(widget.createdAt) ?? DateTime.now();
    final elapsed = DateTime.now().difference(created);
    if (elapsed != _elapsed) setState(() => _elapsed = elapsed);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDuration(_elapsed),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _IncidentType {
  const _IncidentType({required this.id, required this.title, required this.icon, required this.color, this.description = ''});
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final String description;

  _IncidentType copyWith({String? description}) => _IncidentType(
    id: id,
    title: title,
    icon: icon,
    color: color,
    description: description ?? this.description,
  );
}

const _incidentTypes = [
  _IncidentType(id: '22222222-2222-2222-2222-222222222222', title: 'Physical Threat', icon: Icons.shield_outlined, color: Color(0xFFFF0000)),
  _IncidentType(id: '22222222-2222-2222-2222-333333333333', title: 'Medical Emergency', icon: Icons.favorite_outline, color: Color(0xFFE63946)),
  _IncidentType(id: '22222222-2222-2222-2222-444444444444', title: 'Theft / Robbery', icon: Icons.work_outline, color: Color(0xFFFFB703)),
  _IncidentType(id: '22222222-2222-2222-2222-555555555555', title: 'Lost / Disoriented', icon: Icons.location_searching, color: Color(0xFF457B9D)),
];
