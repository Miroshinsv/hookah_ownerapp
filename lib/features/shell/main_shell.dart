import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/update/update_dialog.dart';
import '../../core/update/update_service.dart';
import '../auth/providers/auth_provider.dart';
import '../chat/providers/lounge_unread_provider.dart';
import '../chat/providers/unread_messages_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import '../lounges/providers/lounges_provider.dart';
import '../orders/providers/orders_provider.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  final String location;

  const MainShell({super.key, required this.child, required this.location});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _notifSub;
  StreamSubscription<String>? _loungeNotifSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate();
      _checkPendingNotification();
    });
    _notifSub = NotificationService.chatOpenStream.listen(_openChat);
    _loungeNotifSub =
        NotificationService.loungeChatOpenStream.listen(_openLoungeChat);
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _loungeNotifSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(unreadMessagesProvider.notifier).refreshFromStorage();
      ref.read(loungeUnreadProvider.notifier).refreshFromStorage();
    }
  }

  Future<void> _checkUpdate() async {
    final release = await UpdateService.checkForUpdate();
    if (release != null && mounted) {
      await showUpdateDialog(context, release);
    }
  }

  Future<void> _checkPendingNotification() async {
    final orderId = await NotificationService.getPendingChatOpen();
    if (orderId != null && mounted) {
      context.push('/chat/$orderId');
      return;
    }
    final loungeId = await NotificationService.getPendingLoungeChatOpen();
    if (loungeId != null && mounted) {
      if (ref.read(authProvider).isStaff) {
        context.go('/staff-chat');
      } else {
        final lounge = ref
            .read(loungesProvider)
            .lounges
            .where((l) => l.id == loungeId)
            .firstOrNull;
        final name = lounge?.name ?? '';
        context.push(
            '/lounge-chat/$loungeId?name=${Uri.encodeComponent(name)}');
      }
    }
  }

  void _openChat(String orderId) {
    if (mounted) context.push('/chat/$orderId');
  }

  void _openLoungeChat(String loungeId) {
    if (!mounted) return;
    if (ref.read(authProvider).isStaff) {
      context.go('/staff-chat');
      return;
    }
    final lounge = ref
        .read(loungesProvider)
        .lounges
        .where((l) => l.id == loungeId)
        .firstOrNull;
    final name = lounge?.name ?? '';
    context.push('/lounge-chat/$loungeId?name=${Uri.encodeComponent(name)}');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // Keep providers alive for the entire shell lifetime so polling and
    // WS subscriptions never stop between tab switches.
    if (!auth.isStaff) ref.watch(dashboardProvider);
    ref.watch(ordersProvider);
    // Staff needs loungesProvider to resolve lounge name and subscribe to lounge chat WS.
    if (auth.canManageLounges || auth.isStaff) ref.watch(loungesProvider);
    final unreadCount = ref.watch(unreadMessagesProvider).length;
    final loungeUnreadCount = (auth.canManageLounges || auth.isStaff)
        ? ref.watch(loungeUnreadProvider).length
        : 0;

    final tabs = [
      // Дашборд — для владельца, заместителя и администратора
      if (!auth.isStaff)
        _Tab('/dashboard', Icons.dashboard_outlined, Icons.dashboard, 'Дашборд'),
      _Tab('/orders', Icons.receipt_long_outlined, Icons.receipt_long, 'Заказы'),
      // Отзывы — для владельца, заместителя и администратора
      if (!auth.isStaff)
        _Tab('/reviews', Icons.rate_review_outlined, Icons.rate_review, 'Обратная связь'),
      if (auth.canManageLounges)
        _Tab('/lounges', Icons.storefront_outlined, Icons.storefront, 'Кальянные'),
      // Чат с заведением — только для кальянного мастера/персонала
      if (auth.isStaff && auth.loungeId != null)
        _Tab('/staff-chat', Icons.chat_bubble_outline, Icons.chat_bubble, 'Чат'),
    ];

    final currentIndex =
        tabs.indexWhere((t) => widget.location.startsWith(t.path)).clamp(0, tabs.length - 1);

    return Scaffold(
      body: Column(
        children: [
          _UserHeader(
            userId: auth.userId ?? '',
            role: auth.role ?? '',
            onProfile: () => context.push('/profile'),
            onLogout: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: tabs.length < 2 ? null : Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => context.go(tabs[i].path),
          items: tabs.map((t) {
            final ordBadge = t.path == '/orders' && unreadCount > 0;
            final loungeBadge =
                (t.path == '/lounges' || t.path == '/staff-chat') &&
                loungeUnreadCount > 0;
            final badgeCount =
                ordBadge ? unreadCount : (loungeBadge ? loungeUnreadCount : 0);
            final showBadge = ordBadge || loungeBadge;
            return BottomNavigationBarItem(
              icon: showBadge
                  ? Badge.count(count: badgeCount, child: Icon(t.icon))
                  : Icon(t.icon),
              activeIcon: showBadge
                  ? Badge.count(count: badgeCount, child: Icon(t.activeIcon))
                  : Icon(t.activeIcon),
              label: t.label,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  final String userId;
  final String role;
  final VoidCallback onLogout;
  final VoidCallback onProfile;

  const _UserHeader({
    required this.userId,
    required this.role,
    required this.onLogout,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (role) {
      'admin' => 'Администратор',
      'owner' => 'Владелец',
      'deputy' => 'Заместитель',
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
            icon: const Icon(Icons.account_circle_outlined, size: 22),
            color: AppColors.muted,
            tooltip: 'Мой профиль',
            onPressed: onProfile,
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
