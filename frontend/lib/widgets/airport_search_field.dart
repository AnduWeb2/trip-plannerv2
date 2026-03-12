import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class AirportSearchField extends StatefulWidget {
  final String label;
  final IconData prefixIcon;
  final void Function(String iataCode, String displayLabel) onSelected;
  final VoidCallback? onCleared;

  const AirportSearchField({
    super.key,
    required this.label,
    required this.prefixIcon,
    required this.onSelected,
    this.onCleared,
  });

  @override
  State<AirportSearchField> createState() => _AirportSearchFieldState();
}

class _AirportSearchFieldState extends State<AirportSearchField> {
  final _storage = const FlutterSecureStorage();
  final _controller = TextEditingController();
  final _layerLink = LayerLink();
  final _focusNode = FocusNode();

  Timer? _debounce;
  OverlayEntry? _overlay;
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _removeOverlay();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      _removeOverlay();
      if (mounted) setState(() => _suggestions = []);
      return;
    }

    if (mounted) setState(() => _loading = true);

    try {
      final token = await _storage.read(key: 'access_token');
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/user/api/select-destination/$query/'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200 && mounted) {
        final body = jsonDecode(response.body);
        setState(() {
          _suggestions = ((body['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        });
        _showOverlay();
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  void _showOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty || !mounted) return;

    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = _suggestions[i];
                  final iata = item['iataCode'] as String? ?? '';
                  final name = item['name'] as String? ?? '';
                  final city = item['cityName'] as String? ?? '';
                  final country = item['countryName'] as String? ?? '';
                  final isAirport = item['subType'] == 'AIRPORT';
                  final displayLabel = city.isNotEmpty ? '$city ($iata)' : '$name ($iata)';
                  final subtitle = isAirport && name.isNotEmpty ? '$name · $country' : country;

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isAirport ? Icons.flight : Icons.location_city,
                      color: const Color(0xFF5B85AA),
                      size: 20,
                    ),
                    title: Text(displayLabel, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: subtitle.isNotEmpty
                        ? Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]))
                        : null,
                    onTap: () {
                      _hasSelection = true;
                      _controller.text = displayLabel;
                      widget.onSelected(iata, displayLabel);
                      _removeOverlay();
                      setState(() => _suggestions = []);
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: GoogleFonts.poppins(color: Colors.grey[700]),
          prefixIcon: Icon(widget.prefixIcon, color: const Color(0xFF5B85AA)),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5B85AA)),
                  ),
                )
              : _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _debounce?.cancel();
                        _controller.clear();
                        _hasSelection = false;
                        widget.onCleared?.call();
                        _removeOverlay();
                        setState(() => _suggestions = []);
                        _focusNode.requestFocus();
                      },
                    )
                  : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF5B85AA), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (value) {
          if (_hasSelection) {
            _hasSelection = false;
            widget.onCleared?.call();
          }
          _debounce?.cancel();
          if (value.trim().isEmpty) {
            _removeOverlay();
            setState(() => _suggestions = []);
            return;
          }
          _debounce = Timer(
            const Duration(milliseconds: 400),
            () => _search(value.trim()),
          );
        },
        onTap: () {
          if (_suggestions.isNotEmpty) _showOverlay();
        },
      ),
    );
  }
}
