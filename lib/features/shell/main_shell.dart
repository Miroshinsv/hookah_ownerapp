import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/update/update_dialog.dart';
import '../../core/update/update_service.dart';
import '../auth/providers/auth_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import '../orders/providers/orders_provider.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  final String location;

  const MainShell({super.key, required this.child, required this.location});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    final release = await UpdateService.checkForUpdate();
    if (release != null && mounted) {
      await showUpdateDialog(context, release);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // Keep providers alive for the entire shell lifetime so polling and
    // WS subscription never stop between tab switches.
    ref.watch(dashboardProvider);
    ref.watch(ordersProvider);

    final tabs = [
      _Tab('/dashboard', Icons.dashboard_outlined, Icons.dashboard, 'Дашборд'),
      _Tab('/orders', Icons.receipt_long_outlined, Icons.receipt_long, 'Заказы'),
      if (auth.canManageLounges)
        _Tab('/lounges', Icons.storefront_outlined, Icons.storefront, 'Кальянные'),
      if (auth.canManageStaff)
        _Tab('/staff', Icons.people_outline, Icons.people, 'Персонал'),
    ];

    final currentIndex =
        tabs.indexWhere((t) => widget.location.startsWith(t.path)).clamp(0, tabs.length - 1);

    return Scaffold(
      body: Column(
        children: [
          _UserHeader(
            userId: auth.userId ?? '',
            role: auth.role ?? '',
            onLogout: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => context.go(tabs[i].path),
          items: tabs
              .map((t) => BottomNavigationBarItem(
                    icon: Icon(t.icon),
                    activeIcon: Icon(t.activeIcon),
                    label: t.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  final String userId;
  final String role;
  final VoidCallback onLogout;

  const _UserHeader({
    required this.userId,
    required this.role,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (role) {
      'admin' => 'Администратор',
      'owner' => 'Владелец',
      'staff' => 'Персонал',
      _ => role,
    };

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 6,
        left: 16,
        right: 8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  userId,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$roleLabel · v${AppConfig.version}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            color: AppColors.muted,
            tooltip: 'Выйти',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

class _Tab {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _Tab(this.path, this.icon, this.activeIcon, this.label);
}
