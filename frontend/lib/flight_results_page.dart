import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'flight_confirm_page.dart';

class FlightResultsPage extends StatelessWidget {
  final List flights;
  const FlightResultsPage({
    super.key,
    required this.flights,
  });

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flight Results', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: flights.isEmpty
          ? Center(
              child: Text('No flights found.', style: GoogleFonts.poppins(fontSize: 16)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: flights.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, idx) {
                final flight = flights[idx];
                final display = (flight['display'] as Map?) ?? {};
                final airlineName = flight['airline_name'] as String? ?? '';
                final origin = display['origin'] as String? ?? '';
                final destination = display['destination'] as String? ?? '';
                final departure = display['departure'] as String? ?? '';
                final arrival = display['arrival'] as String? ?? '';
                final price = flight['price']?['total'];
                final currency = flight['price']?['currency'] ?? 'EUR';
                final stops = display['stops'] as int? ?? 0;

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.flight, color: Color(0xFF5B85AA), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$airlineName  |  $origin → $destination',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Departure: $departure', style: GoogleFonts.poppins(fontSize: 14)),
                        Text('Arrival: $arrival', style: GoogleFonts.poppins(fontSize: 14)),
                        Text(
                          stops == 0 ? 'Non-stop' : '$stops stop${stops > 1 ? 's' : ''}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: stops == 0 ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (price != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Price: $price $currency',
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF5B85AA)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Estimated price — select flight to see final price',
                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                        const Divider(height: 20),
                        if (flight['checkin_link'] != null) ...[
                          Text('Check-in:', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[600])),
                          const SizedBox(height: 4),
                          _BookButton(label: 'Check-in', onTap: () => _launchUrl(flight['checkin_link'])),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FlightConfirmPage(flight: Map<String, dynamic>.from(flight)),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5B85AA),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text('Select flight', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _BookButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BookButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF5B85AA),
        side: const BorderSide(color: Color(0xFF5B85AA)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

