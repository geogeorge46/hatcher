import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/phase2_providers.dart';

/// Small status chip displayed on the HomeScreen showing whether Geo's
/// gateway phone is online (heartbeat within 3 minutes) or offline.
class GatewayStatusChip extends ConsumerWidget {
  const GatewayStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gwAsync = ref.watch(gatewayStatusProvider);

    return gwAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (gw) {
        final online = gw?.isOnline ?? false;
        final bg = online ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
        final fg = online ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
        final icon = online ? Icons.check_circle : Icons.error_outline;
        final label = online
            ? 'Gateway ✔ online${gw != null && gw.battery >= 0 ? ' (${gw.battery}%)' : ''}'
            : 'Gateway offline';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push('/settings/gateway'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: fg.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
