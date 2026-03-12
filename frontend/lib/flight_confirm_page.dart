import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class FlightConfirmPage extends StatefulWidget {
  final Map<String, dynamic> flight;
  const FlightConfirmPage({super.key, required this.flight});

  @override
  State<FlightConfirmPage> createState() => _FlightConfirmPageState();
}

class _FlightConfirmPageState extends State<FlightConfirmPage> {
  final storage = const FlutterSecureStorage();
  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? pricedOffer;

  @override
  void initState() {
    super.initState();
    _priceOffer();
  }

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
          Uri.parse('http://127.0.0.1:8000/user/api/price-offer/'),
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
        setState(() {
          pricedOffer = body;
        });
      } else {
        String msg = 'Failed to confirm price.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body.containsKey('error')) {
            msg = body['error'].toString();
            if (body.containsKey('details') && body['details'] != null) {
              msg += '\n\nDetails: ${body['details']}';
            }
          } else if (body is Map && body.containsKey('detail')) {
            msg = body['detail'].toString();
          }
        } catch (_) {}
        setState(() {
          errorMessage = msg;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
    } finally {
      setState(() => isLoading = false);
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
    final currency = (pricedDisplay['price_currency'] as String?) ?? widget.flight['price']?['currency'] as String? ?? 'EUR';

    return Scaffold(
      appBar: AppBar(
        title: Text('Confirm Price', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? Center(
                    child: Text(
                      errorMessage!,
                      style: GoogleFonts.poppins(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$airlineName  |  $origin → $destination',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text('Departure: $departure', style: GoogleFonts.poppins(fontSize: 14)),
                      Text('Arrival: $arrival', style: GoogleFonts.poppins(fontSize: 14)),
                      const SizedBox(height: 12),
                      Text(
                        'Confirmed price',
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$price $currency',
                        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF5B85AA)),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Booking step not implemented yet.',
                                  style: GoogleFonts.poppins(),
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5B85AA),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Book this flight', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
