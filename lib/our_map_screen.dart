
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'private_config.dart';
class OurMapScreen extends StatefulWidget {
  const OurMapScreen({super.key});

  @override
  State<OurMapScreen> createState() => _OurMapScreenState();
}

class _OurMapScreenState extends State<OurMapScreen> {
  final MapController _mapController = MapController();

  static const String _chatRoomId = 'private_chat';

  LatLng? _currentLocation;
  bool _loading = true;
  bool _sharing = false;
  bool _busy = false;
  String? _errorMessage;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<Position>? _navigationSubscription;
  DateTime? _lastRerouteAt;
  int _activeStepIndex = 0;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _partnerSubscription;

  LatLng? _partnerLocation;
  bool _partnerSharing = false;
  double _currentBearing = 0;
  StreamSubscription<CompassEvent>? _compassSubscription;
double _compassHeading = 0;
DateTime? _lastCompassWriteAt;
double _partnerBearing = 0;

StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    _ownLocationSubscription;
  List<LatLng> _routePoints = [];
  double? _routeDistanceKm;
  double? _routeDurationMinutes;
  List<Map<String, dynamic>> _routeSteps = [];
  bool _navigationStarted = false;
  String _routeTarget = 'partner';
  LatLng? _homeLocation;
  LatLng? _officeLocation;
  bool _routeLoading = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  LatLng? _searchLocation;
  String _travelMode = 'driving';

  User? get _user => FirebaseAuth.instance.currentUser;

  DocumentReference<Map<String, dynamic>> _locationDocument(
    String uid,
  ) {
    return FirebaseFirestore.instance
        .collection('private_chats')
        .doc(_chatRoomId)
        .collection('live_locations')
        .doc(uid);
  }@override
void initState() {
  super.initState();
  _startCompass();
  _getCurrentLocation();
  _listenToPartner();
  _listenToOwnLocation();
  _loadSavedPlaces();
  _restoreLocationSharing();
}
void _startCompass() {
  _compassSubscription?.cancel();

  _compassSubscription = FlutterCompass.events?.listen((event) {
    if (!mounted) return;

    final heading = event.heading;

    if (heading != null && heading.isFinite) {
      setState(() {
        _compassHeading = (heading + 360) % 360;
        
      });
      _sendCompassHeading(_compassHeading);
    }
  });
}
Future<void> _sendCompassHeading(double heading) async {
  if (!_sharing) return;

  final user = _user;
  if (user == null) return;

  final now = DateTime.now();

  if (_lastCompassWriteAt != null &&
      now.difference(_lastCompassWriteAt!) <
          const Duration(seconds: 2)) {
    return;
  }

  _lastCompassWriteAt = now;

  try {
    await _locationDocument(user.uid).set({
      'bearing': heading,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (e) {
    if (mounted) {
      setState(() {
        _errorMessage = 'Compass update failed: $e';
      });
    }
  }
}
  Future<bool> _checkLocationPermission({
    bool requireBackground = false,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on Location/GPS on your phone.');
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception(
        'Enable location permission in your phone settings.',
      );
    }

    // The map only needs foreground permission. Background live sharing
    // additionally requires Android's "Allow all the time" permission.
    if (requireBackground && permission != LocationPermission.always) {
      throw Exception(
        'For screen-off live sharing, open App info > Permissions > Location '
        'and select "Allow all the time". Then return to UsOnMap and start sharing again.',
      );
    }

    return true;
  }

  Future<void> _getCurrentLocation() async {
    try {
      await _checkLocationPermission(requireBackground: true);

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      setState(() {
        _currentLocation = LatLng(
          position.latitude,
          position.longitude,
        );
        _loading = false;
        _errorMessage = null;
      });

      _mapController.move(_currentLocation!, 16);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

   void _listenToPartner() {
    final user = _user;

    if (user == null) {
      setState(() {
        _errorMessage = 'Please sign in first.';
      });
      return;
    }
   
    // This app is configured for two known accounts.
    // Do not listen to your own location document.
   
final allowedUids = AppPrivateConfig.allowedUids;
    if (!allowedUids.contains(user.uid)) {
      setState(() {
        _errorMessage = 'This account is not authorized.';
      });
      return;
    }

    final partnerUid = allowedUids.firstWhere(
      (uid) => uid != user.uid,
    );

    _partnerSubscription = _locationDocument(partnerUid)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;

        final data = snapshot.data();
        final enabled = snapshot.exists &&
            data?['sharingEnabled'] == true;

        final latitude = data?['latitude'];
        final longitude = data?['longitude'];
        final bearing = data?['bearing'];

final validBearing = bearing is num &&
        bearing.isFinite &&
        bearing >= 0 &&
        bearing < 360
    ? bearing.toDouble()
    : 0.0;

        setState(() {
          _partnerSharing = enabled;
          _partnerBearing = validBearing;

          if (enabled &&
              latitude is num &&
              longitude is num &&
              latitude.toDouble() >= -90 &&
              latitude.toDouble() <= 90 &&
              longitude.toDouble() >= -180 &&
              longitude.toDouble() <= 180) {
            _partnerLocation = LatLng(
              latitude.toDouble(),
              longitude.toDouble(),
            );
          } else {
            _partnerLocation = null;
          }
        });
        if (_routeTarget == 'partner' && _routePoints.isNotEmpty &&
            _partnerSharing && _partnerLocation != null) {
          _calculateRoute('partner');
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Could not read partner location. Check Firestore rules.';
        });
      },
    );
  }
 void _listenToOwnLocation() {
  final user = _user;

  if (user == null) return;

  _ownLocationSubscription?.cancel();

  _ownLocationSubscription = _locationDocument(user.uid).snapshots().listen(
    (snapshot) {
      if (!mounted) return;

      final data = snapshot.data();

      if (data == null) return;

      final sharingEnabled = data['sharingEnabled'] == true;

      final latitude = data['latitude'];
      final longitude = data['longitude'];
      final bearing = data['bearing'];

      if (sharingEnabled &&
          latitude is num &&
          longitude is num &&
          latitude.isFinite &&
          longitude.isFinite &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180) {
        setState(() {
          _sharing = true;
          _currentLocation = LatLng(
            latitude.toDouble(),
            longitude.toDouble(),
          );

          if (bearing is num &&
              bearing.isFinite &&
              bearing >= 0 &&
              bearing < 360) {
            _currentBearing = bearing.toDouble();
          }
        });
      } else {
        setState(() {
          _sharing = false;
        });
      }
    },
    onError: (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Location listener error: $error';
      });
    },
  );
}
Future<void> _restoreLocationSharing() async {
  final prefs = await SharedPreferences.getInstance();

  final shouldResume =
      prefs.getBool('location_sharing_consent') ?? false;

  if (!shouldResume || !mounted) return;

  await _startSharing(restoring: true);
}
 Future<void> _startSharing({bool restoring = false}) async {
  if (_busy || (_sharing && !restoring)) return;

    final user = _user;
    if (user == null) {
      _showMessage('Please sign in first.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      await _checkLocationPermission();

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // Write only the signed-in user's own location document.
await _locationDocument(user.uid).set({
  'uid': user.uid,
  'sharingEnabled': true,
  'latitude': position.latitude,
  'longitude': position.longitude,
  'bearing': _compassHeading,
  'updatedAt': FieldValue.serverTimestamp(),
});
      if (!mounted) return;

      setState(() {
        _currentLocation = LatLng(
          position.latitude,
          position.longitude,
        );
        _sharing = true;
      });
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('location_sharing_consent', true);
      await _positionSubscription?.cancel();
      // Android foreground notification keeps location updates active while
      // the screen is locked or another app is in the foreground. The user
      // can stop this explicitly with the existing Stop Sharing control.
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: Duration(seconds: 10),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: 'UsOnMap live location is active',
            notificationText: 'Your location is being shared with your partner.',
            enableWakeLock: true,
          ),
        ),
      ).listen(
        (position) async {
          if (!_sharing || !mounted) return;

          final location = LatLng(
            position.latitude,
            position.longitude,
          );

          setState(() {
            _currentLocation = location;
          });
          if (_routeTarget != 'partner' && _routePoints.isNotEmpty) {
            _calculateRoute(_routeTarget);
          } else if (_routeTarget == 'partner' && _routePoints.isNotEmpty &&
              _partnerLocation != null) {
            _calculateRoute('partner');
          }

          try {
            await _locationDocument(user.uid).set({
              'uid': user.uid,
              'sharingEnabled': true,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'bearing': _compassHeading,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {
            if (!mounted) return;
            setState(() {
              _errorMessage =
                  'Could not send location. Check your internet connection and Firestore rules.';
            });
          }
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _errorMessage = 'Could not update location.';
          });
        },
      );

      _showMessage('Live location sharing started.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _stopSharing() async {
    if (_busy) return;

    final user = _user;
    if (user == null) return;

    setState(() {
      _busy = true;
    });

    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      final prefs = await SharedPreferences.getInstance();
await prefs.setBool('location_sharing_consent', false);

      // Keep the document but mark sharing disabled.
      await _locationDocument(user.uid).set({
        'uid': user.uid,
        'sharingEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _sharing = false;
      });

      _showMessage('Live location sharing stopped.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Could not stop sharing. Check your internet connection and Firestore rules.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }


  Future<void> _loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    LatLng? readPlace(String key) {
      final lat = prefs.getDouble('${key}_lat');
      final lon = prefs.getDouble('${key}_lon');
      if (lat == null || lon == null) return null;
      return LatLng(lat, lon);
    }
    if (!mounted) return;
    setState(() {
      _homeLocation = readPlace('home');
      _officeLocation = readPlace('office');
    });
  }

  Future<void> _saveCurrentPlace(String place) async {
    final current = _currentLocation;
    if (current == null) {
      _showMessage('Current location is not available yet.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${place}_lat', current.latitude);
    await prefs.setDouble('${place}_lon', current.longitude);
    if (!mounted) return;
    setState(() {
      if (place == 'home') {
        _homeLocation = current;
      } else {
        _officeLocation = current;
      }
    });
    _showMessage('${place == 'home' ? 'Home' : 'Office'} location saved on this device.');
  }

  LatLng? get _selectedDestination {
    switch (_routeTarget) {
      case 'search':
        return _searchLocation;
      case 'home':
        return _homeLocation;
      case 'office':
        return _officeLocation;
      default:
        return _partnerSharing ? _partnerLocation : null;
    }
  }

  Future<void> _calculateRoute(String target, {String? profile}) async {
    final start = _currentLocation;
    LatLng? end;
    setState(() {
      _routeTarget = target;
      _routeLoading = true;
      _errorMessage = null;
    });
    end = _selectedDestination;
    final selectedProfile = profile ?? _travelMode;
    if (start == null || end == null) {
      if (mounted) {
        setState(() {
          _routeLoading = false;
          _routePoints = [];
          _routeDistanceKm = null;
          _routeDurationMinutes = null;
        });
      }
      _showMessage(target == 'partner'
          ? 'Your partner is not sharing their location.'
          : 'Save this location first.');
      return;
    }
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/$selectedProfile/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Route service unavailable.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
        throw Exception('No driving route found.');
      }
      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final geometry = route['geometry']['coordinates'] as List;
      final legs = route['legs'] as List? ?? [];
      final firstLeg = legs.isNotEmpty ? legs.first as Map<String, dynamic> : <String, dynamic>{};
      final rawSteps = firstLeg['steps'] as List? ?? [];
      final parsedSteps = rawSteps.whereType<Map<String, dynamic>>().map((step) {
        final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
        final type = '${maneuver['type'] ?? 'continue'}';
        final modifier = '${maneuver['modifier'] ?? ''}';
        final road = '${step['name'] ?? ''}'.trim();
        final instruction = _buildInstruction(type, modifier, road);
        return <String, dynamic>{
          'instruction': instruction,
          'distance': (step['distance'] as num? ?? 0).toDouble(),
        };
      }).toList();
      final points = geometry.map((point) {
        final coords = point as List;
        return LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
      }).toList();
      if (!mounted) return;
      setState(() {
        _routePoints = points;
        _routeDistanceKm = (route['distance'] as num).toDouble() / 1000;
        _routeDurationMinutes = (route['duration'] as num).toDouble() / 60;
        _routeSteps = parsedSteps;
        if (_activeStepIndex >= parsedSteps.length) _activeStepIndex = 0;
      });
      if (points.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: [start, end],
            padding: const EdgeInsets.fromLTRB(50, 100, 50, 210),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showMessage('Could not calculate route. Check internet and try again.');
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  String _buildInstruction(String type, String modifier, String road) {
    final turn = switch (type) {
      'depart' => 'Start',
      'arrive' => 'Arrive at your destination',
      'turn' => 'Turn',
      'new name' => 'Continue',
      'merge' => 'Merge',
      'on ramp' => 'Take the ramp',
      'off ramp' => 'Take the exit ramp',
      'fork' => 'Keep',
      'end of road' => 'At the end of the road, turn',
      'roundabout' || 'rotary' => 'Enter the roundabout and',
      'continue' => 'Continue',
      'notification' => 'Continue',
      _ => 'Continue',
    };
    final direction = modifier.isEmpty ? '' : ' $modifier';
    final street = road.isEmpty ? '' : ' onto $road';
    if (type == 'arrive') return turn;
    if (type == 'depart') return road.isEmpty ? 'Start your journey' : 'Start on $road';
    return '$turn$direction$street';
  }

  Future<void> _startNavigation() async {
    if (_routePoints.isEmpty || _selectedDestination == null) {
      _showMessage('Choose a destination and calculate a route first.');
      return;
    }
    final permission = await Geolocator.checkPermission();
    var granted = permission;
    if (permission == LocationPermission.denied) {
      granted = await Geolocator.requestPermission();
    }
    if (granted == LocationPermission.denied ||
        granted == LocationPermission.deniedForever) {
      _showMessage('Location permission is required for live navigation.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showMessage('Turn on GPS to start navigation.');
      return;
    }
    if (!mounted) return;
    setState(() { _navigationStarted = true; _activeStepIndex = 0; });
    final current = _currentLocation;
    if (current != null) _mapController.move(current, 17);
    // Navigation has its own GPS stream so it works even when location sharing is off.
    await _navigationSubscription?.cancel();
    _navigationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(_onNavigationPosition, onError: (_) {
      if (mounted) _showMessage('GPS updates paused. Check location permission and GPS.');
    });
    _showMessage('Live navigation started. Keep GPS enabled.');
  }

  void _onNavigationPosition(Position position) {
    if (!mounted || !_navigationStarted) return;
    final current = LatLng(position.latitude, position.longitude);
    setState(() => _currentLocation = current);
    // Keep the user's marker in view as they move.
    try { _mapController.move(current, 17); } catch (_) {}

    if (_routePoints.isNotEmpty) {
      double nearest = double.infinity;
      for (final point in _routePoints) {
        final d = Geolocator.distanceBetween(current.latitude, current.longitude,
            point.latitude, point.longitude);
        if (d < nearest) nearest = d;
      }
      // Recalculate only when clearly off-route; throttle network requests.
      final now = DateTime.now();
      if (nearest > 70 &&
          (_lastRerouteAt == null || now.difference(_lastRerouteAt!) > const Duration(seconds: 20))) {
        _lastRerouteAt = now;
        _calculateRoute(_routeTarget);
      }
      // Advance the next-turn instruction as the user approaches its step distance.
      if (_routeSteps.isNotEmpty && _activeStepIndex < _routeSteps.length - 1) {
        final step = _routeSteps[_activeStepIndex];
        final meters = (step['distance'] as num? ?? 0).toDouble();
        if (nearest < 25 && meters < 100) {
          setState(() => _activeStepIndex = (_activeStepIndex + 1).clamp(0, _routeSteps.length - 1));
        }
      }
    }
  }

  void _stopNavigation() {
    _navigationSubscription?.cancel();
    _navigationSubscription = null;
    if (mounted) setState(() => _navigationStarted = false);
    _showMessage('Navigation stopped.');
  }

  void _schedulePlaceSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    // Wait until typing pauses to avoid sending a request for every keystroke.
    _searchDebounce = Timer(const Duration(milliseconds: 650), () {
      _searchPlaces(query);
    });
  }

  Future<List<Map<String, dynamic>>> _queryPlaces(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '8',
      'countrycodes': 'in',
      'accept-language': 'en',
    });
    final response = await http.get(uri, headers: {
      'User-Agent': 'UsOnMap/1.0 (location search)',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Search unavailable');
    }
    return (jsonDecode(response.body) as List)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> _searchPlaces(String query) async {
    final cleaned = query.trim();
    if (cleaned.length < 3) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    final requestId = ++_searchRequestId;
    if (mounted) setState(() => _searching = true);
    try {
      // First search the exact phrase across India. If a short local landmark
      // name is not found, retry with common Maharashtra/Pune context.
      var results = await _queryPlaces(cleaned);
      if (results.isEmpty && !cleaned.toLowerCase().contains('india')) {
        results = await _queryPlaces('$cleaned, Maharashtra, India');
      }
      if (results.isEmpty &&
          !cleaned.toLowerCase().contains('pune') &&
          !cleaned.toLowerCase().contains('maharashtra')) {
        results = await _queryPlaces('$cleaned, Pune, Maharashtra, India');
      }
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _searchResults = results);
      if (results.isEmpty) _showMessage('No places found. Try adding the city name.');
    } catch (_) {
      if (mounted && requestId == _searchRequestId) {
        _showMessage('Place search failed. Check your internet and try again.');
      }
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    final lat = double.tryParse('${result['lat']}');
    final lon = double.tryParse('${result['lon']}');
    if (lat == null || lon == null) return;
    setState(() {
      _searchLocation = LatLng(lat, lon);
      _routeTarget = 'search';
      _searchResults = [];
      _searchController.text = '${result['display_name'] ?? 'Selected destination'}';
    });
    await _calculateRoute('search');
  }

  Future<void> _openTransitRoute(String mode) async {
    // Keep the in-app search and mode buttons. For walking and public transit,
    // open Google Maps directions because the current OSRM service only
    // provides driving routes. Transit mode lets Google Maps offer bus/train
    // options where local transit data is available.
    final destination = _selectedDestination;
    if (destination == null) {
      _showMessage('Search for a destination first, then choose a travel mode.');
      return;
    }
    final origin = _currentLocation;
    final googleMode = mode == 'walking' ? 'walking' : 'transit';
    final params = <String, String>{
      'api': '1',
      'destination': '${destination.latitude},${destination.longitude}',
      'travelmode': googleMode,
    };
    if (origin != null) {
      params['origin'] = '${origin.latitude},${origin.longitude}';
    }
    if (mode == 'bus') params['transit_mode'] = 'bus';
    if (mode == 'train') params['transit_mode'] = 'train';
    final uri = Uri.https('www.google.com', '/maps/dir/', params);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showMessage('Could not open Google Maps.');
    } catch (_) {
      if (mounted) _showMessage('Could not open Google Maps. Check that it is installed or try again.');
    }
  }

  Widget _travelModeButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: selected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
              )),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
@override
void dispose() {
  _positionSubscription?.cancel();
  _navigationSubscription?.cancel();
  _partnerSubscription?.cancel();
  _ownLocationSubscription?.cancel();
  _compassSubscription?.cancel();
  _searchDebounce?.cancel();
  _searchController.dispose();
  _mapController.dispose();
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    final initialCenter =
        _currentLocation ?? const LatLng(19.7515, 75.7139);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenHeight = MediaQuery.sizeOf(context).height;

    const mapTileFilter = ColorFilter.matrix(<double>[
      -0.185, -0.482, -0.074, 0, 200,
      -0.185, -0.482, -0.074, 0, 200,
      -0.185, -0.482, -0.074, 0, 200,
      0, 0, 0, 1, 0,
    ]);

    Widget locationMarker({
      required IconData icon,
      required Color color,
      required String label,
      required double bearing,
    }) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.38),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
child: AnimatedRotation(
  turns: bearing / 360,
  duration: const Duration(milliseconds: 400),
  child: Icon(
    Icons.navigation_rounded,
    color: Colors.white,
    size: 24,
  ),
),            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 5),
              ],
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 18,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Explore & Navigate',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              'Your world, together',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.favorite_rounded,
                color: colors.onPrimaryContainer,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _currentLocation == null ? 6 : 15,
            ),
            children: [
              if (isDark)
                ColorFiltered(
                  colorFilter: mapTileFilter,
                  child: TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.us_on_map',
                  ),
                )
              else
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.us_on_map',
                ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 9,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5,
                      color: colors.primary,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 82,
                      height: 76,
                      alignment: Alignment.topCenter,
                      child: locationMarker(
                        icon: Icons.person_rounded,
                        color: const Color(0xFF2878F0),
                        label: 'You',
                        bearing: _compassHeading,                      ),
                    ),
                  if (_partnerSharing && _partnerLocation != null)
                    Marker(
                      point: _partnerLocation!,
                      width: 92,
                      height: 76,
                      alignment: Alignment.topCenter,
                      child: locationMarker(
                        icon: Icons.favorite_rounded,
                        color: const Color(0xFFE94D91),
                        label: 'Partner',
                        bearing: _partnerBearing,
                      ),
                    ),
                  if (_homeLocation != null)
                    Marker(
                      point: _homeLocation!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.home_rounded,
                        color: Colors.green,
                        size: 36,
                        shadows: [Shadow(color: Colors.white, blurRadius: 8)],
                      ),
                    ),
                  if (_officeLocation != null)
                    Marker(
                      point: _officeLocation!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.work_rounded,
                        color: Colors.deepOrange,
                        size: 34,
                        shadows: [Shadow(color: Colors.white, blurRadius: 8)],
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // Floating search panel.
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: Column(
              children: [
                Material(
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.16),
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(22),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _searchPlaces,
                    onChanged: _schedulePlaceSearch,
                    decoration: InputDecoration(
                      hintText: 'Search places, address or destination',
                      hintStyle: TextStyle(color: colors.onSurfaceVariant),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colors.primary,
                        size: 25,
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.my_location_rounded),
                              tooltip: 'My location',
                              onPressed: _getCurrentLocation,
                            ),
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 17,
                        horizontal: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: BoxConstraints(
                      maxHeight: screenHeight * 0.34,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 16),
                      ],
                    ),
                    child: ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: colors.primaryContainer,
                            child: Icon(
                              Icons.place_rounded,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            '${result['name'] ?? result['display_name'] ?? 'Place'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${result['display_name'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSearchResult(result),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          if (_loading)
            Center(
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      SizedBox(width: 12),
                      Text('Finding your location...'),
                    ],
                  ),
                ),
              ),
            ),

          if (_errorMessage != null)
            Positioned(
              left: 16,
              right: 16,
              top: _searchResults.isNotEmpty ? 150 : 82,
              child: Material(
                elevation: 5,
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: colors.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Quick recenter button, kept below the search bar.
          Positioned(
            right: 16,
            top: 160,
            child: Material(
              elevation: 7,
              color: colors.surface,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Center on my location',
                onPressed: _loading ? null : _getCurrentLocation,
                icon: Icon(Icons.my_location_rounded, color: colors.primary),
                iconSize: 24,
              ),
            ),
          ),

          if (_searchResults.isEmpty)
            Positioned.fill(
              child: DraggableScrollableSheet(
                initialChildSize: 0.18,
                minChildSize: 0.13,
                maxChildSize: 0.78,
                snap: true,
                snapSizes: const [0.18, 0.78],
                builder: (context, sheetScrollController) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Material(
                      color: colors.surface,
                      elevation: 14,
                      shadowColor: Colors.black.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(26),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        controller: sheetScrollController,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colors.outlineVariant,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Your journey',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: (_sharing
                                        ? Colors.green
                                        : colors.onSurfaceVariant)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: _sharing
                                        ? Colors.green
                                        : colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _sharing ? 'LIVE SHARING' : 'NOT SHARING',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_routeDistanceKm != null &&
                            _routeDurationMinutes != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.route_rounded,
                                  color: colors.onPrimaryContainer,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${_routeDistanceKm!.toStringAsFixed(1)} km',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: colors.onPrimaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  'About ${_routeDurationMinutes!.round()} min',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          'TRAVEL MODE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 9,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            Tooltip(
                              message: 'Car',
                              child: _travelModeButton(
                                icon: Icons.directions_car_rounded,
                                label: 'Car',
                                selected: _travelMode == 'driving',
                                onPressed: () {
                                  setState(() => _travelMode = 'driving');
                                  if (_selectedDestination != null) {
                                    _calculateRoute(
                                      _routeTarget,
                                      profile: 'driving',
                                    );
                                  }
                                },
                              ),
                            ),
                            Tooltip(
                              message: 'Walking',
                              child: _travelModeButton(
                                icon: Icons.directions_walk_rounded,
                                label: 'Walk',
                                selected: false,
                                onPressed: () => _openTransitRoute('walking'),
                              ),
                            ),
                            Tooltip(
                              message: 'Bus',
                              child: _travelModeButton(
                                icon: Icons.directions_bus_rounded,
                                label: 'Bus',
                                selected: false,
                                onPressed: () => _openTransitRoute('bus'),
                              ),
                            ),
                            Tooltip(
                              message: 'Train',
                              child: _travelModeButton(
                                icon: Icons.train_rounded,
                                label: 'Train',
                                selected: false,
                                onPressed: () => _openTransitRoute('train'),
                              ),
                            ),
                          ],
                        ),
                        if (_searchLocation != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _routeLoading
                                  ? null
                                  : () => _calculateRoute('search'),
                              icon: const Icon(Icons.alt_route_rounded),
                              label: const Text('Calculate route'),
                            ),
                          ),
                        ],
                        if (_routePoints.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _navigationStarted
                                  ? _stopNavigation
                                  : _startNavigation,
                              icon: Icon(
                                _navigationStarted
                                    ? Icons.stop_circle_rounded
                                    : Icons.navigation_rounded,
                              ),
                              label: Text(
                                _navigationStarted
                                    ? 'Stop navigation'
                                    : 'GO — Start navigation',
                              ),
                            ),
                          ),
                        ],
                        if (_navigationStarted && _routeSteps.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.turn_right_rounded,
                                size: 30,
                                color: colors.onPrimaryContainer,
                              ),
                              title: Text(
                                'NEXT TURN',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${_routeSteps[_activeStepIndex]['instruction'] ?? 'Continue'}',
                                style: TextStyle(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: Text(
                                _routeDistanceKm == null
                                    ? ''
                                    : '${_routeDistanceKm!.toStringAsFixed(1)} km left',
                                style: TextStyle(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'DIRECTIONS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _routeSteps.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final step = _routeSteps[index];
                                final meters =
                                    (step['distance'] as num? ?? 0).toDouble();
                                final distanceText = meters >= 1000
                                    ? '${(meters / 1000).toStringAsFixed(1)} km'
                                    : '${meters.round()} m';
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: colors.primaryContainer,
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    '${step['instruction'] ?? 'Continue'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    distanceText,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'QUICK DESTINATIONS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _routeLoading
                                  ? null
                                  : () => _calculateRoute('partner'),
                              icon: const Icon(Icons.favorite_rounded, size: 17),
                              label: const Text('Partner'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _routeLoading
                                  ? null
                                  : () => _calculateRoute('home'),
                              icon: const Icon(Icons.home_rounded, size: 17),
                              label: const Text('Home'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _routeLoading
                                  ? null
                                  : () => _calculateRoute('office'),
                              icon: const Icon(Icons.work_rounded, size: 17),
                              label: const Text('Office'),
                            ),
                          ],
                        ),
                        if (_routeLoading) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 0,
                          children: [
                            TextButton.icon(
                              onPressed: () => _saveCurrentPlace('home'),
                              icon: const Icon(Icons.add_home_rounded, size: 17),
                              label: const Text('Save as Home'),
                            ),
                            TextButton.icon(
                              onPressed: () => _saveCurrentPlace('office'),
                              icon: const Icon(Icons.business_rounded, size: 17),
                              label: const Text('Save as Office'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: _sharing
                                    ? Colors.green.withValues(alpha: 0.14)
                                    : colors.surface,
                                child: Icon(
                                  _sharing
                                      ? Icons.location_on_rounded
                                      : Icons.location_searching_rounded,
                                  color: _sharing
                                      ? Colors.green
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _user == null
                                          ? 'Not signed in'
                                          : _sharing
                                              ? 'Your location is being shared'
                                              : 'Location sharing is off',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      _partnerSharing
                                          ? 'Partner location is available'
                                          : 'Waiting for partner location',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_partnerSharing)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.green,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor:
                                  _sharing ? colors.error : colors.primary,
                              foregroundColor: _sharing
                                  ? colors.onError
                                  : colors.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : _sharing
                                    ? _stopSharing
                                    : _startSharing,
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _sharing
                                        ? Icons.stop_rounded
                                        : Icons.share_location_rounded,
                                  ),
                            label: Text(
                              _busy
                                  ? 'Please wait...'
                                  : _sharing
                                      ? 'Stop sharing live location'
                                      : 'Share live location',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                                                             ],
                    ),
                  ),
                ),
              );
                               },
              ),
            ),
        ],
      ),
    );
  }
}