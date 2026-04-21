import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'services/auth_service.dart';

class HotelMapPage extends StatefulWidget {
  const HotelMapPage({super.key});

  @override
  State<HotelMapPage> createState() => _HotelMapPageState();
}

class _PlaceSuggestion {
  final String placeId;
  final String description;
  const _PlaceSuggestion({required this.placeId, required this.description});
}

class _HotelMapPageState extends State<HotelMapPage> {
  final Completer<GoogleMapController> _controller = Completer();
  bool _loading = false;
  Timer? _debounce;
  Set<Marker> _markers = {};
  int _hotelCount = 0;

  // Camera tracking
  LatLng _currentCenter = const LatLng(44.4268, 26.1025);

  // Search bar state
  final TextEditingController _searchController = TextEditingController();
  List<_PlaceSuggestion> _suggestions = [];
  bool _searchLoading = false;
  final FocusNode _searchFocus = FocusNode();
  final _storage = const FlutterSecureStorage();

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(44.4268, 26.1025), 
    zoom: 12,
  );

  Future<String?> _getToken() => _storage.read(key: 'access_token');

  void _handleAuthFailure() {
    AuthService.clearSession();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  Future<void> _fetchSuggestions(String input) async {
    if (input.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searchLoading = true);
    String? token = await _getToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/api/places/autocomplete/').replace(
      queryParameters: {'q': input},
    );
    try {
      http.Response response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null) {
          _handleAuthFailure();
          return;
        }
        response = await http.get(uri, headers: {
          'Authorization': 'Bearer $token',
        });
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final predictions = data['predictions'] as List<dynamic>;
        setState(() {
          _suggestions = predictions
              .map((p) => _PlaceSuggestion(
                    placeId: p['placeId'] as String,
                    description: p['description'] as String,
                  ))
              .toList();
        });
      } else {
        debugPrint('[Places] autocomplete error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[Places] autocomplete exception: $e');
    } finally {
      setState(() => _searchLoading = false);
    }
  }

  Future<void> _goToPlace(String placeId) async {
    String? token = await _getToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/api/places/details/').replace(
      queryParameters: {'place_id': placeId},
    );
    try {
      http.Response response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null) {
          _handleAuthFailure();
          return;
        }
        response = await http.get(uri, headers: {
          'Authorization': 'Bearer $token',
        });
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['lat'] as double;
        final lng = data['lng'] as double;
        final controller = await _controller.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(lat, lng), zoom: 14),
          ),
        );
        setState(() {
          _suggestions = [];
          _searchFocus.unfocus();
        });
      } else {
        debugPrint('[Places] details error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[Places] details exception: $e');
    }
  }

  Future<void> _fetchHotels(LatLng center) async {
    setState(() => _loading = true);
    String? token = await _getToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/api/hotels/search/').replace(
      queryParameters: {
        'lat': center.latitude.toString(),
        'lng': center.longitude.toString(),
        'radius': '5',
      },
    );
    try {
      http.Response response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null) {
          _handleAuthFailure();
          return;
        }
        response = await http.get(uri, headers: {
          'Authorization': 'Bearer $token',
        });
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hotels = data['hotels'] as List<dynamic>;
        final warning = data['warning'] as String?;
        if (warning != null && warning.isNotEmpty) {
          debugPrint('[Hotels] warning: $warning');
        }
        debugPrint('[Hotels] received ${hotels.length} hotels from API');
        final newMarkers = <Marker>{};
        for (final h in hotels) {
          final latRaw = h['lat'];
          final lngRaw = h['lng'];
          debugPrint('[Hotels] hotel: ${h['name']} lat=$latRaw lng=$lngRaw');
          if (latRaw == null || lngRaw == null) continue;
          final lat = (latRaw as num).toDouble();
          final lng = (lngRaw as num).toDouble();
          final name = h['name'] as String? ?? 'Hotel';
          final address = h['address'] as String? ?? '';
          newMarkers.add(Marker(
            markerId: MarkerId(h['hotelId'] as String? ?? name),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            onTap: () => _showHotelBottomSheet(name, address),
          ));
        }
        debugPrint('[Hotels] placing ${newMarkers.length} markers on map');
        setState(() {
          _markers = newMarkers;
          _hotelCount = newMarkers.length;
        });
      } else {
        debugPrint('[Hotels] search error ${response.statusCode}: ${response.body}');
        setState(() {
          _markers = {};
          _hotelCount = 0;
        });
      }
    } catch (e) {
      debugPrint('[Hotels] search exception: $e');
      setState(() {
        _markers = {};
        _hotelCount = 0;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onCameraMove(CameraPosition position) {
    _currentCenter = position.target;
  }

  void _onCameraIdle() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _fetchHotels(_currentCenter);
    });
  }

  void _showHotelBottomSheet(String name, String address) {
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
            if (address.isNotEmpty)
              Text(address, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
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
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          // Search bar overlay
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Caută o zonă sau un hotel...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _suggestions = []);
                                  },
                                )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      _fetchSuggestions(value);
                    },
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on, color: Colors.blue),
                          title: Text(
                            suggestion.description,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () {
                            _searchController.text = suggestion.description;
                            _goToPlace(suggestion.placeId);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_loading)
            const Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            bottom: 24,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Text(
                _loading ? 'Se caută...' : '$_hotelCount hoteluri găsite',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
