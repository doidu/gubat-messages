import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sms_message.dart';
import '../services/sms_service.dart';
import '../services/spam_detection_service.dart';
import '../services/contact_service.dart';
import '../utils/message_processor.dart';
import 'settings_screen.dart';
import 'blocked_numbers_screen.dart';
import 'search_screen.dart';
import 'conversation_screen.dart';
import '../widgets/spam_confirmation_dialog.dart';
import '../widgets/conversation_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final SmsService _smsService = SmsService();
  bool _isLoading = true;
  final Set<String> _selectedAddresses = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh messages when app comes back to foreground
      _refreshMessages();
    }
  }

  Future<void> _refreshMessages() async {
    await _smsService.refreshMessages();
    await ContactService().refreshContacts();
    setState(() {}); // Force rebuild to update contact names in conversations
  }

  void _showOfflineSnackbar() {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot connect to GubatDetectAPI, spam messages might go to inbox'),
          backgroundColor: Colors.red.shade400,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _initializeSms() async {
    await _smsService.initialize();
    SmsService.showOfflineSnackbar = _showOfflineSnackbar;
    SpamDetectionService.showOfflineSnackbar = _showOfflineSnackbar;

    // Check connectivity and show snackbar if offline
    await _checkConnectivityOnLoad();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _checkConnectivityOnLoad() async {
    try {
      final spamService = SpamDetectionService();
      final isApiReachable = await spamService.checkApiKey();
      if (!isApiReachable) {
        _showOfflineSnackbar();
      }
    } catch (e) {
      _showOfflineSnackbar();
    }
  }

  void _toggleSelection(String address) {
    setState(() {
      if (_selectedAddresses.contains(address)) {
        _selectedAddresses.remove(address);
        if (_selectedAddresses.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedAddresses.add(address);
        _isSelectionMode = true;
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectedAddresses.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _showSpamDialog() async {
    final isMarkingAsSpam = _selectedIndex == 0;

    // Count total messages from selected addresses
    final sourceBox = _selectedIndex == 0
        ? Hive.box<SmsMessage>('inbox')
        : Hive.box<SmsMessage>('spam');

    int totalMessageCount = 0;
    for (var address in _selectedAddresses) {
      totalMessageCount += sourceBox.values.where((msg) => msg.address == address).length;
    }

    bool shouldReport = false;
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => SpamConfirmationDialog(
        messageCount: totalMessageCount,
        isMarkingAsSpam: isMarkingAsSpam,
        onConfirm: (reportAsSpam) {
          shouldReport = reportAsSpam;
        },
      ),
    );

    if (shouldProceed == true) {
      // Perform the marking action
      for (var address in _selectedAddresses) {
        if (isMarkingAsSpam) {
          // Mark entire conversation as spam
          await MessageProcessorIsolate.markConversationAsSpam(address);
        } else {
          // Unmark entire conversation as spam
          await MessageProcessorIsolate.markConversationAsNotSpam(address);
        }
      }

      // Show success snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMarkingAsSpam
                ? '${_selectedAddresses.length == 1 ? 'Conversation' : 'Conversations'} moved to spam folder successfully'
                : '${_selectedAddresses.length == 1 ? 'Conversation' : 'Conversations'} restored to inbox successfully',
            ),
            backgroundColor: Colors.green.shade400,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }

      // Report asynchronously if requested
      if (shouldReport && isMarkingAsSpam) {
        await _reportSpamAsync();
      }

      setState(() {
        _selectedAddresses.clear();
        _isSelectionMode = false;
      });
    }
  }

  Future<void> _reportSpamAsync() async {
    bool reportSuccess = true;
    for (var address in _selectedAddresses) {
      final success = await _smsService.reportConversationAsSpam(address);
      if (!success) {
        reportSuccess = false;
        break; // If any conversation fails to report, mark as failed
      }
    }

    // Show toast
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reportSuccess ? 'Message reported successfully. Thank you!' : 'Failed to report message'),
          backgroundColor: reportSuccess ? Colors.green.shade400 : Colors.red.shade400,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _blockSelectedSenders() async {
    final box = Hive.box<String>('blocked_numbers');

    int blockedCount = 0;
    int alreadyBlockedCount = 0;
    for (var address in _selectedAddresses) {
      if (!box.values.contains(address)) {
        try {
          await box.add(address);
          blockedCount++;
        } catch (e) {
          // Handle error if needed
        }
      } else {
        alreadyBlockedCount++;
      }
    }

    if (mounted) {
      String message;
      if (alreadyBlockedCount == _selectedAddresses.length) {
        message = 'Selected number/s already blocked';
      } else {
        message = '$blockedCount number${blockedCount == 1 ? '' : 's'} blocked';
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    setState(() {
      _selectedAddresses.clear();
      _isSelectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFE8F5E8).withValues(alpha: 0.5),
const Color(0xFFF1F8E9).withValues(alpha: 0.5),
              ],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 4.0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: Color(0xFF4CAF50),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4.0,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back, size: 24),
                onPressed: _cancelSelection,
              )
            : const Padding(
                padding: EdgeInsets.only(left: 12.0),
                child: Center(
                  child: Text(
                    'Gubat Messages',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
        leadingWidth: _isSelectionMode ? null : 180,
        actions: _isSelectionMode
            ? [
                TextButton(
                  onPressed: _blockSelectedSenders,
                  child: const Text(
                    'Block',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: TextButton(
                    onPressed: _showSpamDialog,
                    child: Text(
                      _selectedIndex == 0 ? 'Mark as Spam' : 'Unmark as Spam',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search, size: 24),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SearchScreen(isSpamFolder: _selectedIndex == 1),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 24),
                    onSelected: (value) {
                      if (value == 'settings') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SettingsScreen()),
                        );
                      } else if (value == 'blocked') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const BlockedNumbersScreen()),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'settings',
                        child: ListTile(
                          leading: Icon(Icons.settings, size: 20),
                          title: Text('Settings'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'blocked',
                        child: ListTile(
                          leading: Icon(Icons.block, size: 20),
                          title: Text('Blocked Numbers'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
      ),
      body: _selectedIndex == 0 ? _buildInbox() : _buildSpamFolder(),
      bottomNavigationBar: SizedBox(
        height: 64,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedIndex = 0;
                    _selectedAddresses.clear();
                    _isSelectionMode = false;
                  });
                },
                child: Container(
                  color: Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _selectedIndex == 0 ? const Color(0xFFE8F5E8) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.inbox_rounded,
                          color: _selectedIndex == 0 ? const Color(0xFF4CAF50) : Colors.grey.shade600,
                          size: 24,
                        ),
                      ),
                      Text(
                        'Inbox',
                        style: TextStyle(
                          color: _selectedIndex == 0 ? const Color(0xFF4CAF50) : Colors.grey.shade600,
                          fontSize: 11,
                          fontWeight: _selectedIndex == 0 ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedIndex = 1;
                    _selectedAddresses.clear();
                    _isSelectionMode = false;
                  });
                },
                child: Container(
                  color: Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _selectedIndex == 1 ? const Color(0xFFE8F5E8) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.report_gmailerrorred,
                          color: _selectedIndex == 1 ? const Color(0xFF4CAF50) : Colors.grey.shade600,
                          size: 24,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Spam',
                          style: TextStyle(
                            color: _selectedIndex == 1 ? const Color(0xFF4CAF50) : Colors.grey.shade600,
                            fontSize: 11,
                            fontWeight: _selectedIndex == 1 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ]
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInbox() {
    return ValueListenableBuilder(
      valueListenable: Hive.box<SmsMessage>('inbox').listenable(),
      builder: (context, Box<SmsMessage> box, _) {
        if (box.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refreshMessages,
            color: const Color(0xFF4CAF50),
            child: const Center(
              child: Text('No messages in inbox'),
            ),
          );
        }

        final conversations = _groupByAddress(box.values.toList());

        final sortedAddresses = conversations.keys.toList()
          ..sort((a, b) {
            final aLatest = conversations[a]!.first.date;
            final bLatest = conversations[b]!.first.date;
            return bLatest.compareTo(aLatest);
          });

        return RefreshIndicator(
          onRefresh: _refreshMessages,
          color: const Color(0xFF4CAF50),
          child: ListView.builder(
            itemCount: sortedAddresses.length,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            itemBuilder: (context, index) {
              final address = sortedAddresses[index];
              final messages = conversations[address]!;
              final latestMessage = messages.first;

              return ConversationTile(
                address: address,
                messages: messages,
                latestMessage: latestMessage,
                isSpam: false,
                isSelected: _selectedAddresses.contains(address),
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleSelection(address);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConversationScreen(
                          address: address,
                          isSpamFolder: false,
                        ),
                      ),
                    );
                  }
                },
                onLongPress: () => _toggleSelection(address),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSpamFolder() {
    return ValueListenableBuilder(
      valueListenable: Hive.box<SmsMessage>('spam').listenable(),
      builder: (context, Box<SmsMessage> box, _) {
        if (box.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refreshMessages,
            color: const Color(0xFF4CAF50),
            child: const Center(
              child: Text('No spam messages'),
            ),
          );
        }

        final conversations = _groupByAddress(box.values.toList());

        final sortedAddresses = conversations.keys.toList()
          ..sort((a, b) {
            final aLatest = conversations[a]!.first.date;
            final bLatest = conversations[b]!.first.date;
            return bLatest.compareTo(aLatest);
          });

        return RefreshIndicator(
          onRefresh: _refreshMessages,
          color: const Color(0xFF4CAF50),
          child: ListView.builder(
            itemCount: sortedAddresses.length,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            itemBuilder: (context, index) {
              final address = sortedAddresses[index];
              final messages = conversations[address]!;
              final latestMessage = messages.first;

              return ConversationTile(
                address: address,
                messages: messages,
                latestMessage: latestMessage,
                isSpam: true,
                isSelected: _selectedAddresses.contains(address),
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleSelection(address);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConversationScreen(
                          address: address,
                          isSpamFolder: true,
                        ),
                      ),
                    );
                  }
                },
                onLongPress: () => _toggleSelection(address),
              );
            },
          ),
        );
      },
    );
  }

  Map<String, List<SmsMessage>> _groupByAddress(List<SmsMessage> messages) {
    final Map<String, List<SmsMessage>> grouped = {};
    
    for (var message in messages) {
      if (!grouped.containsKey(message.address)) {
        grouped[message.address] = [];
      }
      grouped[message.address]!.add(message);
    }

    // Sort messages in each group by date (newest first)
    for (var key in grouped.keys) {
      grouped[key]!.sort((a, b) => b.date.compareTo(a.date));
    }

    return grouped;
  }
}
