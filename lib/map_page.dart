import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _controller;
  final Set<Marker> _markers = <Marker>{};

  // Initial camera position centered on India - removed const and static
  final CameraPosition _initial = const CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 5,
  );

  @override
  void initState() {
    super.initState();
    // Add some sample markers
    _markers.add(
      const Marker(
        markerId: MarkerId('sample_farm'),
        position: LatLng(20.5937, 78.9629),
        infoWindow: InfoWindow(
          title: 'Sample Farm',
          snippet: 'A nearby farming location',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Farm Map'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: GoogleMap(
        initialCameraPosition: _initial,
        onMapCreated: _onMapCreated,
        markers: _markers,
        // Location features - require permissions
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        // Map UI settings
        zoomControlsEnabled: true,
        mapToolbarEnabled: true,
        compassEnabled: true,
        // Map type
        mapType: MapType.normal,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Example: Animate to a specific location
          if (_controller != null) {
            _controller!.animateCamera(
              CameraUpdate.newCameraPosition(_initial),
            );
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}