import 'package:flutter/material.dart';

class SpamConfirmationDialog extends StatefulWidget {
  final int messageCount;
  final bool isMarkingAsSpam;
  final void Function(bool reportAsSpam) onConfirm;

  const SpamConfirmationDialog({
    super.key,
    required this.messageCount,
    required this.isMarkingAsSpam,
    required this.onConfirm,
  });

  @override
  State<SpamConfirmationDialog> createState() => _SpamConfirmationDialogState();
}

class _SpamConfirmationDialogState extends State<SpamConfirmationDialog> {
  bool _reportAsSpam = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isMarkingAsSpam ? 'Mark as Spam' : 'Unmark as Spam'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isMarkingAsSpam
                ? 'Mark this message${widget.messageCount > 1 ? 's' : ''} as spam and move to spam folder?\n*No info other than the message body will be sent.'
                : 'Unmark this message${widget.messageCount > 1 ? 's' : ''} as spam and restore to inbox?',
          ),
          if (widget.isMarkingAsSpam) ...[
            CheckboxListTile(
              title: const Text('Report this as spam?'),
              value: _reportAsSpam,
              onChanged: (value) {
                setState(() {
                  _reportAsSpam = value ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.green,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onConfirm(_reportAsSpam && widget.isMarkingAsSpam);
            Navigator.of(context).pop(true);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          child: const Text('Yes'),
        ),
      ],
    );
  }
}
