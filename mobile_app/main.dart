import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'mqtt_services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LiveTrackingScreen(),
    );
  }
}

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with TickerProviderStateMixin {
  late AnimationController _lineController;
  late AnimationController _orbController;
  GoogleMapController? _mapController;
  late MqttService mqtt;

  LatLng currentLocation = const LatLng(25.227011, 51.483643);
  bool _isFollowing = true;
  static const LatLng driverLocation = LatLng(25.227011, 51.483643);

  LatLng? _startLocation;
  final List<LatLng> _routePoints = [];
  final Set<Polyline> _polylines = {};

  // Geofence bounds
  // Red geofence
final List<LatLng> _safeZonePoints = [
  const LatLng(25.693586, 50.957777), // top-left
  const LatLng(25.677565, 51.488727), // top-right
  const LatLng(24.948384, 51.548740), // bottom-right
  const LatLng(24.980187, 50.920399), // bottom-left
];


  // Geofence alert state
  bool _isOutside = false;
int _exitCount = 0;
final List<DateTime> _exitTimestamps = [];

// School entry state
bool _isInsideSchool = false;
int _schoolEntryCount = 0;
final List<DateTime> _schoolEntryTimestamps = [];


    
  void _updateTrack(LatLng newLocation) {
    if (_startLocation == null) {
      _startLocation = newLocation;
    }

    if (_routePoints.isEmpty || _routePoints.last != newLocation) {
      _routePoints.add(newLocation);
    }

    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('live_track'),
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );
  }

  bool? _wasInsideZone;

void _checkGeofence(LatLng location) {
  final bool isInsideRedNow = _isPointInPolygon(location, _safeZonePoints);

  // Red zone: count exits
  if (_isOutside == false && isInsideRedNow == false) {
    _exitCount++;
    _isOutside = true;
    _exitTimestamps.add(DateTime.now());
  } else if (_isOutside == true && isInsideRedNow == true) {
    _isOutside = false;
  }
  String _formatDateTime(DateTime dt) {
  return "${dt.day}/${dt.month}/${dt.year} "
      "${dt.hour.toString().padLeft(2, '0')}:"
      "${dt.minute.toString().padLeft(2, '0')}";
}
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
  int intersections = 0;

  for (int i = 0; i < polygon.length; i++) {
    final LatLng p1 = polygon[i];
    final LatLng p2 = polygon[(i + 1) % polygon.length];

    final bool intersects = ((p1.longitude > point.longitude) !=
            (p2.longitude > point.longitude)) &&
        (point.latitude <
            (p2.latitude - p1.latitude) *
                    (point.longitude - p1.longitude) /
                    (p2.longitude - p1.longitude) +
                p1.latitude);

    if (intersects) {
      intersections++;
    }
  }

  return intersections % 2 == 1;
}
  @override
  void initState() {
    super.initState();

    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    mqtt = MqttService();

    mqtt.onLocationUpdate = (lat, lng) {
      final newLocation = LatLng(lat, lng);

      if (!mounted) return;

      setState(() {
        currentLocation = newLocation;
        _updateTrack(newLocation);
        _checkGeofence(newLocation);
      });

      if (_isFollowing) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(newLocation),
        );
      }
    };

    mqtt.connect();
  }

  @override
  void dispose() {
    _lineController.dispose();
    _orbController.dispose();
    _mapController?.dispose();
    mqtt.disconnect();
    super.dispose();
  }

  Future<void> _goToDriverLocation() async {
    _isFollowing = true;

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: currentLocation,
          zoom: 16.8,
          tilt: 0,
          bearing: 0,
        ),
      ),
    );
  }

  Future<void> _zoomIn() async {
    final currentZoom = await _mapController?.getZoomLevel();
    await _mapController?.animateCamera(
      CameraUpdate.zoomTo((currentZoom ?? 16) + 1),
    );
  }

  Future<void> _zoomOut() async {
    final currentZoom = await _mapController?.getZoomLevel();
    await _mapController?.animateCamera(
      CameraUpdate.zoomTo((currentZoom ?? 16) - 1),
    );
  }

  Widget _buildMapBackground() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: driverLocation,
            zoom: 16,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          onCameraMoveStarted: () {
            _isFollowing = false;
          },
          mapType: MapType.normal,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          buildingsEnabled: true,
          trafficEnabled: false,
          indoorViewEnabled: true,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          markers: {
            if (_startLocation != null)
              Marker(
                markerId: const MarkerId('start'),
                position: _startLocation!,
                infoWindow: const InfoWindow(title: 'Start Point'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
              ),
            Marker(
              markerId: const MarkerId('driver'),
              position: currentLocation,
              infoWindow: const InfoWindow(title: 'Current Location'),
            ),
          },
          polylines: _polylines,
          polygons: {
  Polygon(
    polygonId: const PolygonId('geofence'),
    points: _safeZonePoints,
    strokeColor: Colors.red,
    strokeWidth: 3,
    fillColor: Colors.red.withOpacity(0.08),
  ),
  Polygon(
    polygonId: const PolygonId('school_zone'),
    points: _schoolZonePoints,
    strokeColor: const Color(0xFF8B5CF6),
    strokeWidth: 3,
    fillColor: const Color(0xFF8B5CF6).withOpacity(0.10),
  ),
},
        ),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              final t = _orbController.value;
              final topGlowShift = math.sin(t * 2 * math.pi) * 12;
              final bottomGlowShift = math.cos(t * 2 * math.pi) * 14;

              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0F172A).withOpacity(0.18),
                          const Color(0xFF1E293B).withOpacity(0.03),
                          const Color(0xFF111827).withOpacity(0.10),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: -70 + topGlowShift,
                    left: -45,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF60A5FA).withOpacity(0.24),
                            const Color(0xFF38BDF8).withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 120,
                    right: -80,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFA78BFA).withOpacity(0.14),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -100 + bottomGlowShift,
                    right: -50,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF22C55E).withOpacity(0.20),
                            const Color(0xFF34D399).withOpacity(0.07),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        ...List.generate(4, (index) {
          return AnimatedBuilder(
            animation: _lineController,
            builder: (context, child) {
              final offset =
                  math.sin((_lineController.value * 2 * math.pi) + index) * 10;

              return Positioned(
                top: 150.0 + index * 95 + offset,
                left: 26,
                right: 26,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.09,
                    child: Container(
                      height: 1.4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: const LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0xFFBAE6FD),
                            Color(0xFFC4B5FD),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }

  Widget _buildSmallTopPills() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            _GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: 22,
              backgroundColor: Colors.black.withOpacity(0.18),
              borderColor: Colors.white.withOpacity(0.18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.explore_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    "Live Driver",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              borderRadius: 20,
              backgroundColor: Colors.black.withOpacity(0.18),
              borderColor: Colors.white.withOpacity(0.18),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LiveDot(),
                  SizedBox(width: 8),
                  Text(
                    "Connected",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingStatusChip() {
    return Positioned(
      top: 86,
      right: 16,
      child: _GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 18,
        backgroundColor: const Color(0xFF0F172A).withOpacity(0.20),
        borderColor: Colors.white.withOpacity(0.18),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF86EFAC)),
            SizedBox(width: 6),
            Text(
              "Live GPS",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return Positioned(
      right: 18,
      bottom: 265,
      child: GestureDetector(
        onTap: _goToDriverLocation,
        child: _GlassContainer(
          width: 60,
          height: 60,
          borderRadius: 22,
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFF10B981).withOpacity(0.88),
          borderColor: Colors.white.withOpacity(0.24),
          child: const Icon(
            Icons.explore_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableBottomSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.22,
      minChildSize: 0.13,
      maxChildSize: 0.38,
      builder: (context, scrollController) {
        return _GlassContainer(
          borderRadius: 32,
          padding: EdgeInsets.zero,
          borderColor: Colors.white.withOpacity(0.24),
          backgroundColor: Colors.white.withOpacity(0.76),
          blur: 20,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.04),
                        Colors.black.withOpacity(0.14),
                        Colors.black.withOpacity(0.04),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF22C55E),
                            Color(0xFF10B981),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF22C55E).withOpacity(0.50),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "Driver Online",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFDBEAFE),
                            Color(0xFFC4B5FD),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        "LIVE",
                        style: TextStyle(
                          color: Color(0xFF4338CA),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: "LATITUDE",
                        value: currentLocation.latitude.toStringAsFixed(6),
                        icon: Icons.north_rounded,
                        accent1: const Color(0xFFDBEAFE),
                        accent2: const Color(0xFFE0E7FF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        title: "LONGITUDE",
                        value: currentLocation.longitude.toStringAsFixed(6),
                        icon: Icons.east_rounded,
                        accent1: const Color(0xFFD1FAE5),
                        accent2: const Color(0xFFCCFBF1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _UpdateCard(),
                const SizedBox(height: 12),
                const _UpdateCardExtra(),
                if (_exitCount > 0)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.red.withOpacity(0.12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.red, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isOutside
                    ? "Driver is OUTSIDE safe zone 🚨 ($_exitCount)"
                    : "Driver left zone $_exitCount times",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_exitTimestamps.isNotEmpty)
          Text(
            "Last exit: ${_formatDateTime(_exitTimestamps.last)}",
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    ),
  ),
  if (_schoolEntryCount > 0)
  Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF8B5CF6).withOpacity(0.12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: const Color(0xFF8B5CF6),
        width: 1.5,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.school_rounded,
              color: Color(0xFF8B5CF6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isInsideSchool
                    ? "Driver is INSIDE school zone 🎓 ($_schoolEntryCount)"
                    : "Driver entered school zone $_schoolEntryCount times",
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_schoolEntryTimestamps.isNotEmpty)
          Text(
            "Last school entry: ${_formatDateTime(_schoolEntryTimestamps.last)}",
            style: const TextStyle(
              color: Color(0xFF8B5CF6),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    ),
  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMapBackground(),
          _buildSmallTopPills(),
          _buildFloatingStatusChip(),
          _buildRecenterButton(),
          Positioned(
            right: 18,
            bottom: 340,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _zoomIn,
                  child: _GlassContainer(
                    width: 50,
                    height: 50,
                    borderRadius: 18,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _zoomOut,
                  child: _GlassContainer(
                    width: 50,
                    height: 50,
                    borderRadius: 18,
                    child: const Icon(Icons.remove, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          _buildDraggableBottomSheet(),
        ],
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blur;
  final Color backgroundColor;
  final Color borderColor;
  final double? width;
  final double? height;

  const _GlassContainer({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 24,
    this.blur = 16,
    this.backgroundColor = const Color.fromRGBO(255, 255, 255, 0.14),
    this.borderColor = const Color.fromRGBO(255, 255, 255, 0.18),
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,  
      builder: (context, child) {
        final scale = 1 + (_pulseController.value * 0.35);

        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF22C55E).withOpacity(0.22),
                ),
              ),
            ),
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF22C55E),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accent1;
  final Color accent2;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent1,
    required this.accent2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent1.withOpacity(0.92),
            accent2.withOpacity(0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF7ED).withOpacity(0.95),
            const Color(0xFFFEF3C7).withOpacity(0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.7),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                "LAST UPDATE",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            "Just now",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCardExtra extends StatelessWidget {
  const _UpdateCardExtra();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFEDE9FE).withOpacity(0.92),
            const Color(0xFFDBEAFE).withOpacity(0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.7),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_rounded, size: 16, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                "STATUS",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            "Tracking active",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
