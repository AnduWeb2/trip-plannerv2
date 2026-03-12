import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/airport_search_field.dart';
import 'flight_results_page.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class FlightAvailabilityPage extends StatefulWidget {
  const FlightAvailabilityPage({super.key});

  @override
  State<FlightAvailabilityPage> createState() => _FlightAvailabilityPageState();
}

class _FlightAvailabilityPageState extends State<FlightAvailabilityPage> {
  final storage = const FlutterSecureStorage();
  final TextEditingController adultsController = TextEditingController(text: '1');
  String? _originCode;
  String? _destinationCode;
  DateTime? departureDate;
  DateTime? returnDate;
  String tripType = 'oneway';
  bool isLoading = false;

  @override
  void dispose() {
    adultsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isDeparture}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        if (isDeparture) {
          departureDate = picked;
          if (returnDate != null && returnDate!.isBefore(departureDate!)) {
            returnDate = null;
          }
        } else {
          returnDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    final origin = _originCode ?? '';
    final destination = _destinationCode ?? '';
    final adults = adultsController.text.trim();

    if (origin.isEmpty || destination.isEmpty) {
      _showError('Validation', 'Please select an origin and destination airport.');
      return;
    }
    if (departureDate == null) {
      _showError('Validation', 'Please select a departure date.');
      return;
    }
    if (tripType == 'round' && returnDate == null) {
      _showError('Validation', 'Please select a return date for round-trip.');
      return;
    }

    setState(() => isLoading = true);
    try {
      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final queryParams = {
        'origin': origin,
        'destination': destination,
        'departureDate': formatDate(departureDate!),
        'trip_type': tripType,
        'adults': adults,
      };
      if (tripType == 'round' && returnDate != null) {
        queryParams['arrivalDate'] = formatDate(returnDate!);
      }
      final uri = Uri.parse('http://127.0.0.1:8000/user/api/search-flight/').replace(queryParameters: queryParams);
      Future<http.Response> sendRequest(String? token) {
        return http.get(
          uri,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      }

      String? token = await storage.read(key: 'access_token');
      http.Response response = await sendRequest(token);

      if (response.statusCode == 401) {
        final refreshed = await _refreshAccessToken();
        if (refreshed != null) {
          token = refreshed;
          response = await sendRequest(token);
        }
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List flights = body is List ? body : (body['offers'] ?? []);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FlightResultsPage(
                flights: flights,
              ),
            ),
          );
        }
      } else {
        String errorMsg = 'Failed to fetch flights.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map) {
            // Backend validation payload: { error: "...", missing: [...] }
            if (response.statusCode == 400 && body['missing'] is List) {
              final missing = (body['missing'] as List).map((e) => e.toString()).toList();
              const labels = {
                'origin': 'Origin',
                'destination': 'Destination',
                'departureDate': 'Departure Date',
                'arrivalDate': 'Return Date',
                'trip_type': 'Trip Type',
                'adults': 'Adults',
              };
              final missingLabels = missing.map((k) => labels[k] ?? k).toList();
              errorMsg = 'Please provide: ${missingLabels.join(', ')}.';
            } else if (body.containsKey('error')) {
              errorMsg = body['error'].toString();
              if (body.containsKey('details') && body['details'] != null) {
                errorMsg += '\n\nDetails: ${body['details']}';
              }
            } else if (body.containsKey('detail')) {
              errorMsg = body['detail'].toString();
            }
          }
        } catch (_) {}
        _showError('Error (${response.statusCode})', errorMsg);
      }
    } catch (e) {
      _showError('Error', e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<String?> _refreshAccessToken() async {
    try {
      final refreshToken = await storage.read(key: 'refresh_token');
      if (refreshToken == null) return null;

      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/user/api/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccess = data['access'] as String?;
        final newRefresh = data['refresh'] as String?;
        if (newAccess != null) {
          await storage.write(key: 'access_token', value: newAccess);
          if (newRefresh != null) {
            await storage.write(key: 'refresh_token', value: newRefresh);
          }
          return newAccess;
        }
      }
    } catch (_) {}

    return null;
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red)),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.poppins(color: const Color(0xFF5B85AA), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Flight Availability', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search Flights', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            AirportSearchField(
              label: 'Origin',
              prefixIcon: Icons.flight_takeoff,
              onSelected: (code, _) => setState(() => _originCode = code),
              onCleared: () => setState(() => _originCode = null),
            ),
            const SizedBox(height: 16),
            AirportSearchField(
              label: 'Destination',
              prefixIcon: Icons.flight_land,
              onSelected: (code, _) => setState(() => _destinationCode = code),
              onCleared: () => setState(() => _destinationCode = null),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(isDeparture: true),
                    child: AbsorbPointer(
                      child: CustomTextField(
                        controller: TextEditingController(text: departureDate != null ? '${departureDate!.year}-${departureDate!.month.toString().padLeft(2, '0')}-${departureDate!.day.toString().padLeft(2, '0')}' : ''),
                        label: 'Departure Date',
                        hint: 'Select date',
                        prefixIcon: Icons.date_range,
                      ),
                    ),
                  ),
                ),
                if (tripType == 'round') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _pickDate(isDeparture: false),
                      child: AbsorbPointer(
                        child: CustomTextField(
                          controller: TextEditingController(text: returnDate != null ? '${returnDate!.year}-${returnDate!.month.toString().padLeft(2, '0')}-${returnDate!.day.toString().padLeft(2, '0')}' : ''),
                          label: 'Return Date',
                          hint: 'Select date',
                          prefixIcon: Icons.date_range,
                        ),
                      ),
                    ),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Trip Type:', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: tripType,
                  items: const [
                    DropdownMenuItem(value: 'oneway', child: Text('One-way')),
                    DropdownMenuItem(value: 'round', child: Text('Round-trip')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      tripType = val!;
                      if (tripType == 'oneway') returnDate = null;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: adultsController,
              label: 'Adults',
              hint: 'Number of adults',
              prefixIcon: Icons.person,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),
            CustomButton(
              label: 'Search Flights',
              onPressed: () => _submit(),
              isLoading: isLoading,
              icon: Icons.search,
            ),
          ],
        ),
      ),
    );
  }
}
