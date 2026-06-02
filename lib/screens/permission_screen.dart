import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'home_screen.dart';
import '../services/contact_service.dart';

class PermissionScreen extends StatefulWidget {
  final HiveAesCipher? cipher;

  const PermissionScreen({super.key, required this.cipher});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  int currentStep = 0;

  final List<PermissionStep> permissionSteps = [
    PermissionStep(
      permission: Permission.sms,
      title: 'SMS Access',
      description: 'Required to read exisiting and incoming messages',
      icon: Icons.message,
    ),
    PermissionStep(
      permission: Permission.contacts,
      title: 'Contacts Access',
      description: 'Required to identify and whitelist all contacts known contacts',
      icon: Icons.contacts,
    ),

    PermissionStep(
      permission: Permission.notification,
      title: 'Notification Permission',
      description: 'Required to enable notifications when new messages are received',
      icon: Icons.notifications,
    ),
    PermissionStep(
      permission: null,
      title: 'Internet Connection Required',
      description: 'Our spam filter requires internet connection. Other core functionalities still work offline\n*All SMS data are encrypted before sending to GubatDetectAPI',
      icon: Icons.wifi,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    bool allGranted = true;
    for (var step in permissionSteps) {
      if (step.permission != null) {
        final status = await step.permission!.status;
        if (!status.isGranted) {
          allGranted = false;
          break;
        }
      }
    }

    if (allGranted && mounted) {
      await ContactService().initialize(widget.cipher);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    }
  }

  Future<void> _requestPermission() async {
    final permission = permissionSteps[currentStep].permission;

    if (permission != null) {
      // Request actual permission
      final status = await permission.request();

      if (status.isGranted) {
        if (currentStep < permissionSteps.length - 1) {
          setState(() {
            currentStep++;
          });
        } else {
          if (mounted) {
            await ContactService().initialize(widget.cipher);
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
              );
            }
          }
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          _showSettingsDialog();
        }
      }
    } else {
      // No permission to request, just proceed to next step
      if (currentStep < permissionSteps.length - 1) {
        setState(() {
          currentStep++;
        });
      } else {
        if (mounted) {
          await ContactService().initialize(widget.cipher);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
        }
      }
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text('Please grant permission from app settings to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = permissionSteps[currentStep];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Progress indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  permissionSteps.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: index <= currentStep
                          ? Colors.green
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 60),
              // Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  step.icon,
                  size: 60,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 40),
              // Title
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Description
              Text(
                step.description,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              // Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _requestPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    step.permission != null ? 'Grant Permission' : 'Continue',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionStep {
  final Permission? permission;
  final String title;
  final String description;
  final IconData icon;

  PermissionStep({
    required this.permission,
    required this.title,
    required this.description,
    required this.icon,
  });
}
