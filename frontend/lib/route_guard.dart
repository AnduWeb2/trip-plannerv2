import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps a protected route and redirects to /login if no access token exists.
class RouteGuard extends StatefulWidget {
  final Widget child;
  const RouteGuard({super.key, required this.child});

  @override
  State<RouteGuard> createState() => _RouteGuardState();
}

class _RouteGuardState extends State<RouteGuard> {
  static const _storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null && mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
