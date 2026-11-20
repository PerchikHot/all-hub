import 'package:flutter/material.dart';

/// Compact, responsive connection header for the built-in Eyra assistant.
/// Actions are deliberately outside the status row: on narrow phones they
/// must wrap rather than collapse the status into a vertical column.
class EyraConnectionHeader extends StatelessWidget {
  const EyraConnectionHeader({
    super.key,
    required this.avatar,
    required this.status,
    required this.connected,
    required this.actions,
  });

  final Widget avatar;
  final String status;
  final bool connected;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Локальная модель',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700)),
            Text(status, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: connected
                ? Colors.green : theme.colorScheme.onSurfaceVariant)),
          ],
        )),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 2, runSpacing: 2, children: actions),
    ]);
  }
}
