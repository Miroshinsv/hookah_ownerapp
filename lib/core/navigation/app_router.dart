import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/screens/lounge_chat_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/lounges/screens/lounge_form_screen.dart';
import '../../features/lounges/screens/lounges_screen.dart';
import '../../features/orders/screens/orders_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/staff/screens/staff_form_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    observers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
    redirect: (context, state) {
      final authenticated = auth.isAuthenticated;
      final onLogin = state.matchedLocation == '/login';

      if (!authenticated && !onLogin) return '/login';
      if (authenticated && onLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (ctx, _) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (_, state, child) => MainShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (ctx, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/orders',
            builder: (ctx, _) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/lounges',
            builder: (ctx, _) => const LoungesScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/chat/:orderId',
        builder: (_, state) =>
            ChatScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/lounge-chat/:loungeId',
        builder: (_, state) => LoungeChatScreen(
          loungeId: state.pathParameters['loungeId']!,
          loungeName: state.uri.queryParameters['name'] ?? '',
        ),
      ),
      GoRoute(
        path: '/lounge-form',
        builder: (ctx, _) => const LoungeFormScreen(),
      ),
      GoRoute(
        path: '/lounge-form/:id',
        builder: (_, state) =>
            LoungeFormScreen(loungeId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/staff-form',
        builder: (ctx, _) => const StaffFormScreen(),
      ),
      GoRoute(
        path: '/staff-form/:id',
        builder: (_, state) =>
            StaffFormScreen(staffId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/profile',
        builder: (ctx, _) => const ProfileScreen(),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Страница не найдена: ${state.error}')),
    ),
  );
});
