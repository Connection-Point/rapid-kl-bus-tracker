import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KL Bus Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellowAccent),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const BusPositionWidget(),
    const MapViewWidget(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KL Bus Tracker')),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'List View',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map View',
          ),
        ],
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}

class BusPositionWidget extends StatefulWidget {
  const BusPositionWidget({super.key});

  @override
  State<BusPositionWidget> createState() => _BusPositionWidgetState();
}

class _BusPositionWidgetState extends State<BusPositionWidget> {
  List<VehicleData> vehicleDataList = [];
  List<VehicleData> filteredVehicleDataList = [];
  bool isLoading = false;
  String errorMessage = '';
  final TextEditingController _searchController = TextEditingController();

  Future<void> fetchVehiclePositions() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      vehicleDataList = [];
      filteredVehicleDataList = [];
    });

    try {
      const url = 'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final feed = gtfs.FeedMessage.fromBuffer(response.bodyBytes);
        final vehicles = feed.entity
            .where((entity) => entity.hasVehicle())
            .map((entity) => entity.vehicle)
            .toList();

        setState(() {
          vehicleDataList = vehicles.map((vehicle) {
            return VehicleData(
              vehicleId: vehicle.vehicle.id ?? 'N/A',
              tripId: vehicle.trip.tripId ?? 'N/A',
              routeId: vehicle.trip.routeId ?? 'N/A',
              latitude: vehicle.position.latitude ?? 0,
              longitude: vehicle.position.longitude ?? 0,
              bearing: vehicle.position.hasBearing() ?? false
                  ? vehicle.position.bearing
                  : null,
              speed: vehicle.position.hasSpeed() ?? false
                  ? vehicle.position.speed
                  : null,
              timestamp: vehicle.timestamp.toInt() ?? 0,
            );
          }).toList();
          filteredVehicleDataList = List.from(vehicleDataList);
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load data: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _filterVehicles(String searchText) {
    setState(() {
      if (searchText.isEmpty) {
        filteredVehicleDataList = List.from(vehicleDataList);
      } else {
        filteredVehicleDataList = vehicleDataList.where((vehicle) {
          final tripInfo = TripInfo.fromString(vehicle.tripId);
          return tripInfo.tripNumber.toLowerCase().contains(searchText.toLowerCase()) ||
              tripInfo.routeId.toLowerCase().contains(searchText.toLowerCase()) ||
              vehicle.vehicleId.toLowerCase().contains(searchText.toLowerCase());
        }).toList();
      }
    });
  }

  String _estimateArrivalTime(VehicleData vehicle) {
    if (vehicle.speed == null || vehicle.speed == 0) return 'Calculating...';

    const double averageDistanceToNextStop = 2000; // meters (example value)
    final double timeInSeconds = averageDistanceToNextStop / vehicle.speed!;

    final now = DateTime.now();
    final arrivalTime = now.add(Duration(seconds: timeInSeconds.toInt()));

    return DateFormat('hh:mm a').format(arrivalTime);
  }

  @override
  void initState() {
    super.initState();
    fetchVehiclePositions();
    _searchController.addListener(() {
      _filterVehicles(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search by Trip No, Route or Vehicle ID',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: fetchVehiclePositions,
                child: const Text('Refresh Data'),
              ),
            ],
          ),
        ),
        if (isLoading) const CircularProgressIndicator(),
        if (errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        Expanded(
          child: filteredVehicleDataList.isEmpty
              ? const Center(
            child: Text('No matching vehicles found'),
          )
              : ListView.builder(
            itemCount: filteredVehicleDataList.length,
            itemBuilder: (context, index) {
              final vehicle = filteredVehicleDataList[index];
              final tripInfo = TripInfo.fromString(vehicle.tripId);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text('Vehicle ID: ${vehicle.vehicleId}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Route: ${tripInfo.routeId} • Trip: ${tripInfo.tripNumber}'),
                      const SizedBox(height: 4),
                      Text('Position: ${vehicle.latitude.toStringAsFixed(4)}, '
                          '${vehicle.longitude.toStringAsFixed(4)}'),
                      if (vehicle.bearing != null)
                        Text('Direction: ${vehicle.bearing!.toStringAsFixed(0)}°'),
                      if (vehicle.speed != null) ...[
                        Text('Speed: ${(vehicle.speed! * 3.6).toStringAsFixed(1)} km/h'),
                        Text('Est. arrival: ${_estimateArrivalTime(vehicle)}'),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Showing ${filteredVehicleDataList.length} of ${vehicleDataList.length} vehicles'),
        ),
      ],
    );
  }
}

class MapViewWidget extends StatefulWidget {
  const MapViewWidget({super.key});

  @override
  State<MapViewWidget> createState() => _MapViewWidgetState();
}

class _MapViewWidgetState extends State<MapViewWidget> {
  List<VehicleData> vehicleDataList = [];
  bool isLoading = false;
  String errorMessage = '';
  LatLng? _center;
  bool _locationPermissionDenied = false;
  LatLng? _currentLocation;

  Future<void> fetchVehiclePositions() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      vehicleDataList = [];
    });

    try {
      const url = 'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final feed = gtfs.FeedMessage.fromBuffer(response.bodyBytes);
        final vehicles = feed.entity
            .where((entity) => entity.hasVehicle())
            .map((entity) => entity.vehicle)
            .toList();

        setState(() {
          vehicleDataList = vehicles.map((vehicle) {
            return VehicleData(
              vehicleId: vehicle.vehicle.id ?? 'N/A',
              tripId: vehicle.trip.tripId ?? 'N/A',
              routeId: vehicle.trip.routeId ?? 'N/A',
              latitude: vehicle.position.latitude ?? 0,
              longitude: vehicle.position.longitude ?? 0,
              bearing: vehicle.position.hasBearing() ?? false
                  ? vehicle.position.bearing
                  : null,
              speed: vehicle.position.hasSpeed() ?? false
                  ? vehicle.position.speed
                  : null,
              timestamp: vehicle.timestamp.toInt() ?? 0,
            );
          }).toList();

          if (vehicleDataList.isNotEmpty) {
            _center = LatLng(
              vehicleDataList.first.latitude,
              vehicleDataList.first.longitude,
            );
          } else {
            _center = const LatLng(3.1390, 101.6869); // Default to KL coordinates
          }
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load data: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationPermissionDenied = true;
        errorMessage = 'Location services are disabled.';
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationPermissionDenied = true;
          errorMessage = 'Location permissions are denied';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationPermissionDenied = true;
        errorMessage = 'Location permissions are permanently denied.';
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _center = _currentLocation;
        _locationPermissionDenied = false;
        errorMessage = '';
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error getting location: $e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    fetchVehiclePositions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_center != null)
            FlutterMap(
              options: MapOptions(
                center: _center,
                zoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                MarkerLayer(
                  markers: [
                    if (_currentLocation != null)
                      Marker(
                        point: _currentLocation!,
                        width: 40,
                        height: 40,
                        builder: (ctx) => const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ...vehicleDataList.map((vehicle) {
                      final tripInfo = TripInfo.fromString(vehicle.tripId);
                      return Marker(
                        point: LatLng(vehicle.latitude, vehicle.longitude),
                        width: 40,
                        height: 40,
                        builder: (ctx) => Container(
                          constraints: BoxConstraints.loose(const Size(40, 40)),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: 0,
                                child: const Icon(
                                  Icons.directions_bus,
                                  color: Colors.blue,
                                  size: 24,
                                ),
                              ),
                              Positioned(
                                top: 20,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tripInfo.routeId,
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          if (isLoading)
            const Center(child: CircularProgressIndicator()),
          if (errorMessage.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'refresh',
            onPressed: fetchVehiclePositions,
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'location',
            onPressed: _getCurrentLocation,
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
    );
  }
}

class VehicleData {
  final String vehicleId;
  final String tripId;
  final String routeId;
  final double latitude;
  final double longitude;
  final double? bearing;
  final double? speed;
  final int timestamp;

  VehicleData({
    required this.vehicleId,
    required this.tripId,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    this.bearing,
    this.speed,
    required this.timestamp,
  });
}

class TripInfo {
  final String fullTripId;
  final String routeId;
  final String tripNumber;
  final String scheduleType;
  final String? departureTime;
  final String? serviceDate;

  TripInfo({
    required this.fullTripId,
    required this.routeId,
    required this.tripNumber,
    required this.scheduleType,
    this.departureTime,
    this.serviceDate,
  });

  factory TripInfo.fromString(String tripId) {
    final parts = tripId.split('_');

    if (parts.length >= 3) {
      return TripInfo(
        fullTripId: tripId,
        scheduleType: parts[0],
        routeId: parts[1],
        tripNumber: parts[2],
        departureTime: parts.length > 3 ? parts[3] : null,
        serviceDate: parts.length > 4 ? parts[4] : null,
      );
    } else {
      return TripInfo(
        fullTripId: tripId,
        scheduleType: 'unknown',
        routeId: tripId.length > 5 ? tripId.substring(0, 5) : tripId,
        tripNumber: tripId,
      );
    }
  }
}