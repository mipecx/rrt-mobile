# RRT System — Mobile Client

Flutter mobile app for the RRT emergency response system with two roles in one app: **tourist** (SOS + live tracking) and **RRT rescuer** (incident handling).

Flutter · geolocator · WebSocket · PostGIS-backed backend

## Features

### Tourist
- Registration / login with phone + OTP
- SOS dispatch: pick incident type, send GPS location + battery level
- Live SOS lifecycle: searching → tracking → arrived → resolved
- Location streaming to the active incident (every 5s)

### RRT rescuer
- Map of active incidents with live markers
- Assigned calls list with crew status management
- Arrive / resolve incident actions
- Location streaming to the backend (every 5s)

### Common
- Real-time updates over WebSocket (`INCIDENT_UPDATE`)
- Editable server URL (dev settings dialog, persisted locally)
- GPS simulation mode for demo/testing

## Quick Start

```bash
cd rrt_client
flutter pub get
flutter run
```

Point the app at the backend via the "Server settings" dialog on the auth screen (default `http://192.168.1.1:8080/api/v1`).

## Project structure

```
rrt_client/
├── lib/
│   ├── main.dart                    # Entry point, DI wiring
│   ├── core/
│   │   ├── services/                # API client, auth, incidents, location, WebSocket
│   │   ├── models/                  # Incident, user models
│   │   └── theme/                   # Colors, Material 3 theme
│   └── features/
│       ├── auth/presentation/       # Login / register screen
│       └── shell/presentation/      # Tourist and RRT shells (1630-line main UI)
├── android/                         # Android app (uses debug signing by default)
├── ios/                             # iOS app
└── pubspec.yaml
```

## Related

- [rrt-backend](https://github.com/mipecx/rrt-backend) — API + WebSocket server
- [rrt-dashboard](https://github.com/mipecx/rrt-dashboard) — dispatcher console
