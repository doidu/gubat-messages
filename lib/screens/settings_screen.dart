import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/spam_detection_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SpamDetectionService _spamService = SpamDetectionService();

  Future<void> _checkApiConnection() async {
    final stopwatch = Stopwatch()..start();
    final isValid = await _spamService.checkApiKey();
    stopwatch.stop();
    final responseTime = stopwatch.elapsedMilliseconds;
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isValid ? 'GubatDetectAPI is running' : 'GubatDetectAPI connection failed'} (${responseTime}ms)'),
          backgroundColor: isValid ? Colors.green.shade400 : Colors.red.shade400,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'App Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Manage Permissions'),
            subtitle: const Text('Go to app permissions settings'),
            onTap: () => openAppSettings(),
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('Test API Connection'),
            subtitle: const Text('Check if connected to GubatDetectAPI'),
            onTap: _checkApiConnection,
          ),

        ],
      ),
    );
  }
}
