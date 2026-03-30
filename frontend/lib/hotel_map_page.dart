import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class HotelMapPage extends StatefulWidget {
  const HotelMapPage({Key? key}) : super(key: key);

  @override
  State<HotelMapPage> createState() => _HotelMapPageState();
}

class _HotelMapPageState extends State<HotelMapPage> {
  final Completer<GoogleMapController> _controller = Completer();
  bool _loading = false;
  Timer? _debounce;
  Set<Marker> _markers = {};

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(44.4268, 26.1025), // Bucuresti default
    zoom: 12,
  );

  void _onCameraIdle() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _loading = true);
      // Simulează un request API și adaugă markere mock
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('hotel1'),
            position: const LatLng(44.4325, 26.1039),
            onTap: () => _showHotelBottomSheet('Hotel Central', '120 EUR/noapte'),
          ),
          Marker(
            markerId: const MarkerId('hotel2'),
            position: const LatLng(44.4268, 26.1025),
            onTap: () => _showHotelBottomSheet('Hotel Lux', '200 EUR/noapte'),
          ),
        };
        _loading = false;
      });
    });
  }

  void _showHotelBottomSheet(String name, String price) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(price, style: const TextStyle(fontSize: 16, color: Colors.blue)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hotel Map')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialPosition,
            onMapCreated: (controller) => _controller.complete(controller),
            onCameraIdle: _onCameraIdle,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          if (_loading)
            const Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
