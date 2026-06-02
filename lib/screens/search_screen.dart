import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sms_message.dart';
import '../services/contact_service.dart';
import 'conversation_screen.dart';
import '../widgets/conversation_tile.dart';

class SearchScreen extends StatefulWidget {
  final bool isSpamFolder;

  const SearchScreen({super.key, required this.isSpamFolder});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50),
          ),
        ),
        title: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Search conversations...',
              hintStyle: TextStyle(color: Colors.white70),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: widget.isSpamFolder
            ? Hive.box<SmsMessage>('spam').listenable()
            : Hive.box<SmsMessage>('inbox').listenable(),
        builder: (context, Box<SmsMessage> box, _) {
          if (_searchQuery.isEmpty) {
            return const Center(
              child: Text('Enter a search term'),
            );
          }

          final contactService = ContactService();
          final searchLower = _searchQuery.toLowerCase();

          // Find messages that match the search
          final matchingMessages = box.values.where((message) {
            final contactName = contactService.getContactName(message.address)?.toLowerCase() ?? '';
            return message.body.toLowerCase().contains(searchLower) ||
                message.address.toLowerCase().contains(searchLower) ||
                contactName.contains(searchLower);
          }).toList();

          if (matchingMessages.isEmpty) {
            return const Center(
              child: Text('No messages found'),
            );
          }

          // Get unique addresses from matching messages
          final matchingAddresses = matchingMessages.map((m) => m.address).toSet();

          // Group messages by address for matching conversations
          final conversations = <String, List<SmsMessage>>{};
          for (var address in matchingAddresses) {
            final messagesForAddress = box.values.where((m) => m.address == address).toList();
            messagesForAddress.sort((a, b) => b.date.compareTo(a.date));
            conversations[address] = messagesForAddress;
          }

          // Sort addresses by latest message date
          final sortedAddresses = conversations.keys.toList()
            ..sort((a, b) {
              final aLatest = conversations[a]!.first.date;
              final bLatest = conversations[b]!.first.date;
              return bLatest.compareTo(aLatest);
            });

          return ListView.builder(
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
                isSpam: widget.isSpamFolder,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConversationScreen(
                        address: address,
                        isSpamFolder: widget.isSpamFolder,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
