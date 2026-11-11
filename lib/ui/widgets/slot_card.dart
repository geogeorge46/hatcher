// lib/ui/widgets/slot_card.dart
//
// A large card representing one egg-rotation slot (morning / noon / evening).
// Displays status, allows the user to log a rotation, snooze the alarm,
// and handles the lockdown confirmation dialog.

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/models/rotation.dart';
import '../../data/models/slot_status.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// A card for a single rotation slot.
///
/// [slotKey]   — machine key: `'morning'`, `'noon'`, or `'evening'`.
/// [slotLabel] — localised display name (e.g. "Morning" / "രാവിലെ").
/// [slotTime]  — configured alarm time string (e.g. "06:00").
/// [symbol]    — rotation symbol for this slot (e.g. "|", "∆", "•").
/// [status]    — current computed [SlotStatus] for this slot.
/// [rotation]  — the [Rotation] record if status is [SlotStatus.done].
/// [isLockdown]— whether the lockdown period is active.
/// [onRotated] — async callback to log a rotation; triggers loading state.
/// [onSnooze]  — called when the user taps the snooze button.
class SlotCard extends StatefulWidget {
  const SlotCard({
    super.key,
    required this.slotKey,
    required this.slotLabel,
    required this.slotTime,
    required this.symbol,
    required this.status,
    this.rotation,
    required this.isLockdown,
    required this.onRotated,
    required this.onSnooze,
  });

  final String slotKey;
  final String slotLabel;
  final String slotTime;
  final String symbol;
  final SlotStatus status;
  final Rotation? rotation;
  final bool isLockdown;
  final Future<void> Function() onRotated;
  final VoidCallback onSnooze;

  @override
  State<SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends State<SlotCard> {
  /// True while [onRotated] is executing so the button shows a spinner.
  bool _loading = false;

  /// Attempts to log the rotation.
  ///
  /// If [isLockdown] is active, first shows a confirmation dialog.
  /// Otherwise logs immediately.
  Future<void> _handleRotation() async {
    if (widget.isLockdown) {
      final confirmed = await _showLockdownDialog();
      if (!confirmed) return;
    }
    setState(() => _loading = true);
    try {
      await widget.onRotated();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shows a dialog asking whether to log a rotation during lockdown.
  Future<bool> _showLockdownDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🔒'),
        content: Text(
          l10n.lockdownLogAnyway,
          style: const TextStyle(fontFamily: 'NotoSansMalayalam'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yes),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final slotAccent = slotColor(widget.slotKey);

    final buttonEnabled = widget.status == SlotStatus.pending ||
        widget.status == SlotStatus.late;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Container(
        constraints: const BoxConstraints(minHeight: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: slotAccent, width: 5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Large symbol ────────────────────────────────────────────
              SizedBox(
                width: 60,
                child: Text(
                  widget.symbol,
                  style: TextStyle(
                    fontSize: 56,
                    color: slotAccent,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),

              // ── Centre column: label + time + status ────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Slot label
                    Text(
                      widget.slotLabel,
                      style: const TextStyle(
                        fontFamily: 'NotoSansMalayalam',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Configured alarm time
                    Text(
                      widget.slotTime,
                      style: const TextStyle(
                        fontFamily: 'NotoSansMalayalam',
                        fontSize: 13,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Status chip
                    _StatusDisplay(
                      status: widget.status,
                      rotation: widget.rotation,
                      l10n: l10n,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // ── Right column: action button ─────────────────────────────
              if (buttonEnabled || widget.isLockdown)
                _ActionColumn(
                  loading: _loading,
                  buttonEnabled: buttonEnabled,
                  isLockdown: widget.isLockdown,
                  l10n: l10n,
                  onRotated: _handleRotation,
                  onSnooze: widget.onSnooze,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StatusDisplay
// ---------------------------------------------------------------------------
class _StatusDisplay extends StatelessWidget {
  const _StatusDisplay({
    required this.status,
    required this.rotation,
    required this.l10n,
  });

  final SlotStatus status;
  final Rotation? rotation;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SlotStatus.done:
        final r = rotation;
        return Row(
          children: [
            const Text('✔', style: TextStyle(color: Colors.green, fontSize: 16)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                r != null
                    ? l10n.statusDoneBy(r.doneBy, r.formattedTime(kTimezone))
                    : l10n.done,
                style: const TextStyle(
                  fontFamily: 'NotoSansMalayalam',
                  color: Colors.green,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

      case SlotStatus.late:
        return Text(
          l10n.statusLate,
          style: const TextStyle(
            fontFamily: 'NotoSansMalayalam',
            color: Color(0xFFF57C00), // orange
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        );

      case SlotStatus.missed:
        return Row(
          children: [
            const Text('✗', style: TextStyle(color: Colors.red, fontSize: 16)),
            const SizedBox(width: 4),
            Text(
              l10n.statusMissed,
              style: const TextStyle(
                fontFamily: 'NotoSansMalayalam',
                color: Colors.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case SlotStatus.pending:
        return Text(
          l10n.statusPending,
          style: TextStyle(
            fontFamily: 'NotoSansMalayalam',
            color: Colors.grey[600],
            fontSize: 13,
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// _ActionColumn
// ---------------------------------------------------------------------------
class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.loading,
    required this.buttonEnabled,
    required this.isLockdown,
    required this.l10n,
    required this.onRotated,
    required this.onSnooze,
  });

  final bool loading;
  final bool buttonEnabled;
  final bool isLockdown;
  final AppLocalizations l10n;
  final VoidCallback onRotated;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(kPrimaryGreen),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // "Rotated ✔" primary action button
        ElevatedButton(
          onPressed: buttonEnabled ? onRotated : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryGreen,
            disabledBackgroundColor: Colors.grey.shade200,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            l10n.btnRotated,
            style: const TextStyle(
              fontFamily: 'NotoSansMalayalam',
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (buttonEnabled) ...[
          const SizedBox(height: 6),
          // Snooze secondary action
          TextButton(
            onPressed: onSnooze,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.btnSnooze,
              style: const TextStyle(
                fontFamily: 'NotoSansMalayalam',
                fontSize: 11,
                color: Colors.black45,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
