import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'services/auth_service.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  final storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> bookings = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => isLoading = true);
    try {
      String? token = await storage.read(key: 'access_token');

      Future<http.Response> sendRequest(String? t) {
        return http.get(
          Uri.parse('${AppConfig.baseUrl}/user/api/bookings/'),
          headers: {if (t != null) 'Authorization': 'Bearer $t'},
        );
      }

      http.Response response = await sendRequest(token);

      if (response.statusCode == 401) {
        final refreshed = await AuthService.refreshAccessToken();
        if (refreshed != null) {
          response = await sendRequest(refreshed);
        }
      }

      if (response.statusCode == 200 && mounted) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          setState(() {
            bookings = decoded.whereType<Map<String, dynamic>>().toList();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _cancelBooking(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel Booking',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to cancel this booking? This action cannot be undone.',
          style: GoogleFonts.poppins(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No, keep it',
                style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Yes, cancel',
                style: GoogleFonts.poppins(
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      String? token = await storage.read(key: 'access_token');

      Future<http.Response> sendRequest(String? t) {
        return http.patch(
          Uri.parse('${AppConfig.baseUrl}/user/api/bookings/$id/cancel/'),
          headers: {
            if (t != null) 'Authorization': 'Bearer $t',
            'Content-Type': 'application/json',
          },
        );
      }

      http.Response response = await sendRequest(token);

      if (response.statusCode == 401) {
        final refreshed = await AuthService.refreshAccessToken();
        if (refreshed != null) {
          response = await sendRequest(refreshed);
        }
      }

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Booking cancelled.',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              backgroundColor: const Color(0xFF5B85AA),
            ),
          );
          _loadBookings();
        } else {
          String msg = 'Failed to cancel booking.';
          try {
            final body = jsonDecode(response.body);
            if (body is Map && body.containsKey('error')) {
              msg = body['error'].toString();
            }
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              backgroundColor: Colors.red,
            ),
          );
        }
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Bookings',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : bookings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flight_outlined,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No bookings yet',
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[500])),
                      const SizedBox(height: 6),
                      Text(
                        'Your booked flights will appear here.',
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBookings,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: bookings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, idx) {
                      final b = bookings[idx];
                      return _BookingCard(
                        booking: b,
                        onCancel: b['status'] == 'CONFIRMED'
                            ? () => _cancelBooking(b['id'] as int)
                            : null,
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── Booking card ────────────────────────────────────────────────────────────
class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onCancel;

  const _BookingCard({required this.booking, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? 'CONFIRMED';
    final isCancelled = status == 'CANCELLED';
    final airline = booking['airline_name'] as String? ?? '';
    final origin = booking['origin'] as String? ?? '';
    final destination = booking['destination'] as String? ?? '';
    final departure = booking['departure_at'] as String? ?? '';
    final arrival = booking['arrival_at'] as String? ?? '';
    final pnr = booking['pnr'] as String? ?? '';
    final price = booking['price_total'] as String? ?? '';
    final currency = booking['price_currency'] as String? ?? 'EUR';
    final stops = booking['stops'] as int? ?? 0;
    final tripType = booking['trip_type'] as String? ?? 'oneway';
    final checkinLink = booking['checkin_link'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCancelled ? Colors.grey[50] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCancelled
              ? Colors.grey[300]!
              : const Color(0xFF5B85AA).withValues(alpha: 0.25),
        ),
        boxShadow: [
          if (!isCancelled)
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
          // Top row: airline + status badge
          Row(
            children: [
              Icon(Icons.flight,
                  size: 20,
                  color:
                      isCancelled ? Colors.grey : const Color(0xFF5B85AA)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$airline  ·  $origin → $destination',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isCancelled ? Colors.grey : const Color(0xFF333333),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCancelled
                      ? Colors.red.withValues(alpha: 0.1)
                      : const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isCancelled ? Colors.red : const Color(0xFF4CAF50),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // PNR
          if (pnr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text('PNR: ',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey[600])),
                  Text(pnr,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF5B85AA),
                          letterSpacing: 1.5)),
                ],
              ),
            ),

          // Departure / arrival
          _infoRow(Icons.flight_takeoff, 'Depart', departure),
          const SizedBox(height: 2),
          _infoRow(Icons.flight_land, 'Arrive', arrival),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                stops == 0
                    ? 'Non-stop'
                    : '$stops stop${stops > 1 ? 's' : ''}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: stops == 0 ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                tripType == 'round' ? 'Round-trip' : 'One-way',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),

          // Check-in link
          if (checkinLink.isNotEmpty && !isCancelled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(checkinLink);
                  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B85AA).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF5B85AA).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_new,
                          size: 16, color: Color(0xFF5B85AA)),
                      const SizedBox(width: 8),
                      Text('Online Check-in',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF5B85AA))),
                    ],
                  ),
                ),
              ),
            ),

          const Divider(height: 20),

          // Price + cancel
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$price $currency',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isCancelled
                        ? Colors.grey
                        : const Color(0xFF5B85AA),
                    decoration:
                        isCancelled ? TextDecoration.lineThrough : null,
                  )),
              if (onCancel != null)
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined,
                      size: 18, color: Colors.red),
                  label: Text('Cancel',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text('$label: ',
            style:
                GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: GoogleFonts.poppins(fontSize: 12)),
      ],
    );
  }
}
