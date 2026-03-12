class AppConfig {
  // Schimbă acest IP cu IP-ul laptopului tău când rulezi pe telefon fizic.
  // Află IP-ul cu: ipconfig getifaddr en0 (macOS)
  // Pentru simulator/emulator: 127.0.0.1
  // Pentru telefon fizic: IP-ul laptopului (ex: 192.168.1.x)
  static const String host = '192.168.1.11';
  static const int port = 8000;

  static String get baseUrl => 'http://$host:$port';
}
