import 'dart:async';
import 'package:flutter/material.dart';

/// A heads-up pop-up banner shown at the top of the screen when the alarm
/// fires while the phone is actively in use (screen on and unlocked).
class HeadsUpOverlay extends StatefulWidget {
  final String symbol;
  final String message;
  final Future<void> Function() onRotated;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;

  const HeadsUpOverlay({
    super.key,
    required this.symbol,
    required this.message,
    required this.onRotated,
    required this.onSnooze,
    required this.onDismiss,
  });

  /// Helper static method to display this overlay over any Navigator context.
  static OverlayEntry? show({
    required BuildContext context,
    required String symbol,
    required String message,
    required Future<void> Function() onRotated,
    required VoidCallback onSnooze,
  }) {
    final overlayState = Overlay.of(context);
    OverlayEntry? entry;

    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 8,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: HeadsUpOverlay(
            symbol: symbol,
            message: message,
            onRotated: () async {
              await onRotated();
              entry?.remove();
            },
            onSnooze: () {
              onSnooze();
              entry?.remove();
            },
            onDismiss: () {
              entry?.remove();
            },
          ),
        ),
      ),
    );

    overlayState.insert(entry);
    return entry;
  }

  @override
  State<HeadsUpOverlay> createState() => _HeadsUpOverlayState();
}

class _HeadsUpOverlayState extends State<HeadsUpOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _offsetAnimation;
  Timer? _autoDismissTimer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();

    // Auto dismiss after 60 seconds of no interaction
    _autoDismissTimer = Timer(const Duration(seconds: 60), () {
      _dismiss();
    });
  }

  Future<void> _dismiss() async {
    _autoDismissTimer?.cancel();
    if (mounted) {
      await _animController.reverse();
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B), // Dark Slate
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Slot symbol
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.symbol,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.amberAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Message
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // Snooze button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            await _dismiss();
                            widget.onSnooze();
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Snooze / സ്നൂസ്'),
                  ),
                ),
                const SizedBox(width: 10),
                // Rotated button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              await widget.onRotated();
                            } finally {
                              if (mounted) {
                                await _dismiss();
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Rotated ✔',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
