import 'package:flutter/material.dart';

import 'core/services/api_client.dart';
import 'core/services/app_state.dart';
import 'core/services/auth_service.dart';
import 'core/services/incident_service.dart';
import 'core/services/location_service.dart';
import 'core/services/realtime_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/shell/presentation/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ThaiGuardApp());
}

class ThaiGuardApp extends StatefulWidget {
  const ThaiGuardApp({super.key});

  @override
  State<ThaiGuardApp> createState() => _ThaiGuardAppState();
}

class _ThaiGuardAppState extends State<ThaiGuardApp> {
  late final AppStateStorage _storage;
  late final AuthService _auth;
  late final IncidentService _incidents;
  late final RealtimeService _realtime;
  late final LocationService _location;
  late Future<bool> _hasSession;

  @override
  void initState() {
    super.initState();
    _storage = AppStateStorage();
    final api = ApiClient(_storage);
    _auth = AuthService(api, _storage);
    _incidents = IncidentService(api);
    _realtime = RealtimeService(_storage);
    _location = LocationService();
    _hasSession = _auth.hasSession();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ThaiGuard',
      theme: AppTheme.lightTheme,
      home: FutureBuilder<bool>(
        future: _hasSession,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!snapshot.data!) {
            return AuthScreen(auth: _auth, storage: _storage, onSignedIn: _restart);
          }
          return AppShell(
            auth: _auth,
            incidents: _incidents,
            location: _location,
            realtime: _realtime,
            storage: _storage,
            onSignedOut: _restart,
          );
        },
      ),
    );
  }

  void _restart() {
    setState(() => _hasSession = _auth.hasSession());
  }
}
