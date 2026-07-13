import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// One row in a [showActionSheet] — icon chip + title(+subtitle), no
/// ListTile chrome. Tapping closes the sheet, then runs [onTap].
class ActionSheetItem {
  ActionSheetItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.iconBg,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? iconBg;
  final Future<void> Function() onTap;

  Widget _build(BuildContext sheetContext) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        onTap: () {
          Navigator.of(sheetContext).pop();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg ?? DesignTokens.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: iconColor ?? DesignTokens.iconStroke,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        color: DesignTokens.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: DesignTokens.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded, drag-handled action sheet — used for "send/share this
/// document" style menus (work screen, history) instead of a plain
/// ListTile list, closer to a native system share sheet.
Future<void> showActionSheet(BuildContext context, List<ActionSheetItem> items) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: DesignTokens.hairline4,
                borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              ),
            ),
            for (var i = 0; i < items.length; i++) ...[
              items[i]._build(sheetContext),
              if (i < items.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Divider(height: 1),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
