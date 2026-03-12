import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class FlightConfirmPage extends StatefulWidget {
  final Map<String, dynamic> flight;
  const FlightConfirmPage({super.key, required this.flight});

  @override
  State<FlightConfirmPage> createState() => _FlightConfirmPageState();
}

class _FlightConfirmPageState extends State<FlightConfirmPage> {
  final storage = const FlutterSecureStorage();
  bool isLoading = true;
  bool isBooking = false;
  String? errorMessage;
  Map<String, dynamic>? pricedOffer;

  List<Map<String, dynamic>> travelers = [];
  List<int> selectedTravelerIds = [];

  @override
  void initState() {
    super.initState();
    _priceOffer();
    _loadTravelers();
  }

  // ─── Price the offer ───────────────────────────────────────────────
  Future<void> _priceOffer() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final payload = {
        'data': {
          'type': 'flight-offers-pricing',
          'flightOffers': [widget.flight],
        }
      };

      Future<http.Response> sendRequest(String? token) {
        return http.post(
          Uri.parse('${AppConfig.baseUrl}/user/api/price-offer/'),
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
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
        setState(() => pricedOffer = body);
      } else {
        String msg = 'Failed to confirm price.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body.containsKey('error')) {
            msg = body['error'].toString();
          }
        } catch (_) {}
        setState(() => errorMessage = msg);
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ─── Load travelers ────────────────────────────────────────────────
  Future<void> _loadTravelers() async {
    try {
      String? token = await storage.read(key: 'access_token');

      Future<http.Response> sendRequest(String? t) {
        return http.get(
          Uri.parse('${AppConfig.baseUrl}/user/api/get-travelers'),
          headers: {if (t != null) 'Authorization': 'Bearer $t'},
        );
      }

      http.Response response = await sendRequest(token);

      if (response.statusCode == 401) {
        final refreshed = await _refreshAccessToken();
        if (refreshed != null) {
          response = await sendRequest(refreshed);
        }
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && mounted) {
          setState(() {
            travelers = decoded.whereType<Map<String, dynamic>>().toList();
          });
        }
      }
    } catch (_) {}
  }

  // ─── Book the flight ───────────────────────────────────────────────
  Future<void> _bookFlight() async {
    if (selectedTravelerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select at least one traveler.',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isBooking = true);

    try {
      // Build Amadeus-compatible traveler list
      final selectedTravelers = travelers
          .where((t) => selectedTravelerIds.contains(t['id']))
          .toList();

      final List<Map<String, dynamic>> amaTravelers = [];
      for (int i = 0; i < selectedTravelers.length; i++) {
        final t = selectedTravelers[i];
        final doc = t['document'] as Map<String, dynamic>?;

        final travelerMap = <String, dynamic>{
          'id': '${i + 1}',
          'dateOfBirth': t['date_of_birth'] ?? '',
          'name': {
            'firstName': t['first_name'] ?? '',
            'lastName': t['last_name'] ?? '',
          },
          'gender': (t['gender'] ?? 'MALE').toString().toUpperCase(),
          'contact': {
            'phones': [
              {
                'deviceType': 'MOBILE',
                'countryCallingCode': (t['phone_country_code'] ?? '1')
                    .toString()
                    .replaceAll('+', ''),
                'number': t['phone_number'] ?? '',
              }
            ],
          },
          'documents': doc != null
              ? [
                  {
                    'documentType':
                        (doc['documentType'] ?? 'PASSPORT').toString().toUpperCase(),
                    'number': doc['documentNumber'] ?? '',
                    'expiryDate': doc['expiryDate'] ?? '',
                    'issuanceCountry': doc['issuanceCountry'] ?? '',
                    'nationality': t['nationality'] ?? '',
                    'holder': true,
                  }
                ]
              : [],
        };
        amaTravelers.add(travelerMap);
      }

      // The offer to book (priced if available, otherwise the original)
      final offerToBook =
          (pricedOffer?['offer'] as Map<String, dynamic>?) ?? widget.flight;

      final bookingPayload = {
        'data': {
          'type': 'flight-order',
          'flightOffers': [offerToBook],
          'travelers': amaTravelers,
        },
      };

      Future<http.Response> sendRequest(String? token) {
        return http.post(
          Uri.parse('${AppConfig.baseUrl}/user/api/book-flight/'),
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(bookingPayload),
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

      if (!mounted) return;

      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final pnr = body['pnr'] ?? '';
        _showBookingSuccess(pnr);
      } else {
        String msg = 'Booking failed.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body.containsKey('error')) {
            msg = body['error'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isBooking = false);
    }
  }

  void _showBookingSuccess(String pnr) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 28),
            const SizedBox(width: 10),
            Text('Booking Confirmed',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pnr.isNotEmpty) ...[
              Text('PNR / Booking Reference:',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B85AA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(pnr,
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5B85AA),
                        letterSpacing: 2)),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Your flight has been booked successfully. You can view it in "My Bookings" under your profile.',
              style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // close dialog
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text('Done',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: const Color(0xFF5B85AA))),
          ),
        ],
      ),
    );
  }

  Future<String?> _refreshAccessToken() async {
    try {
      final refreshToken = await storage.read(key: 'refresh_token');
      if (refreshToken == null) return null;

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/user/api/token/refresh/'),
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

  // ─── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final display = (widget.flight['display'] as Map?) ?? {};
    final airlineName = widget.flight['airline_name']?.toString() ?? '';
    final origin = display['origin'] as String? ?? '';
    final destination = display['destination'] as String? ?? '';
    final departure = display['departure'] as String? ?? '';
    final arrival = display['arrival'] as String? ?? '';

    final pricedDisplay = (pricedOffer?['display'] as Map?) ?? {};
    final price = pricedDisplay['price_total'] ?? widget.flight['price']?['total'];
    final currency = (pricedDisplay['price_currency'] as String?) ??
        widget.flight['price']?['currency'] as String? ??
        'EUR';

    return Scaffold(
      appBar: AppBar(
        title: Text('Confirm & Book',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(errorMessage!,
                        style: GoogleFonts.poppins(color: Colors.red),
                        textAlign: TextAlign.center),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Flight summary card ──
                      _FlightSummaryCard(
                        airlineName: airlineName,
                        origin: origin,
                        destination: destination,
                        departure: departure,
                        arrival: arrival,
                        price: price?.toString() ?? '-',
                        currency: currency,
                      ),
                      const SizedBox(height: 24),

                      // ── Traveler selection ──
                      Text(
                        'Select Travelers',
                        style: GoogleFonts.poppins(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose who will travel on this flight.',
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      if (travelers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No travelers found. Please add travelers in your profile first.',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...travelers.map((t) {
                          final id = t['id'] as int;
                          final isSelected = selectedTravelerIds.contains(id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _TravelerCheckTile(
                              name:
                                  '${t['first_name']} ${t['last_name']}',
                              subtitle:
                                  '${t['nationality'] ?? ''} · ${t['gender'] ?? ''}',
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    selectedTravelerIds.remove(id);
                                  } else {
                                    selectedTravelerIds.add(id);
                                  }
                                });
                              },
                            ),
                          );
                        }),

                      const SizedBox(height: 28),

                      // ── Book button ──
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              (selectedTravelerIds.isNotEmpty && !isBooking)
                                  ? _bookFlight
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5B85AA),
                            disabledBackgroundColor:
                                const Color(0xFF5B85AA).withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 2,
                          ),
                          child: isBooking
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5),
                                    ),
                                    const SizedBox(width: 12),
                                    Text('Booking...',
                                        style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white)),
                                  ],
                                )
                              : Text('Book this flight',
                                  style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ─── Flight summary card widget ──────────────────────────────────────────────
class _FlightSummaryCard extends StatelessWidget {
  final String airlineName, origin, destination, departure, arrival, price, currency;

  const _FlightSummaryCard({
    required this.airlineName,
    required this.origin,
    required this.destination,
    required this.departure,
    required this.arrival,
    required this.price,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF5B85AA).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flight, color: Color(0xFF5B85AA)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$airlineName  ·  $origin → $destination',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(Icons.flight_takeoff, 'Departure', departure),
          const SizedBox(height: 4),
          _infoRow(Icons.flight_land, 'Arrival', arrival),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Confirmed price',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey[600])),
              Text('$price $currency',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5B85AA))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text('$label: ',
            style:
                GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600])),
        Text(value, style: GoogleFonts.poppins(fontSize: 13)),
      ],
    );
  }
}

// ─── Traveler selection tile ─────────────────────────────────────────────────
class _TravelerCheckTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _TravelerCheckTile({
    required this.name,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF5B85AA).withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF5B85AA)
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isSelected
                  ? const Icon(Icons.check_circle,
                      key: ValueKey('checked'),
                      color: Color(0xFF5B85AA),
                      size: 24)
                  : Icon(Icons.radio_button_unchecked,
                      key: const ValueKey('unchecked'),
                      color: Colors.grey[400],
                      size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
