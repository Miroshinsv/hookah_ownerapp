import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class ReleaseInfo {
  final String tagName;
  final String version;
  final String changelog;
  final String downloadUrl;
  final DateTime publishedAt;

  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    required this.publishedAt,
  });
}

class UpdateService {
  static const _repo = 'Miroshinsv/hookah_ownerapp';
  static const _apiUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  /// Returns [ReleaseInfo] if a newer version is available, otherwise null.
  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version; // e.g. "1.0.0"

      final response = await http
          .get(Uri.parse(_apiUrl), headers: {
            'Accept': 'application/vnd.github.v3+json',
          })
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').trim();
      if (tagName.isEmpty) return null;

      final latest = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (!_isNewer(latest, current)) return null;

      final changelog = (data['body'] as String? ?? '').trim();
      final publishedAt = DateTime.tryParse(
            data['published_at'] as String? ?? '',
          ) ??
          DateTime.now();

      // Prefer APK asset; fall back to the releases page.
      final assets = (data['assets'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final apkAsset = assets.firstWhere(
        (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
        orElse: () => <String, dynamic>{},
      );
      final downloadUrl = apkAsset['browser_download_url'] as String? ??
          'https://github.com/$_repo/releases/latest';

      return ReleaseInfo(
        tagName: tagName,
        version: latest,
        changelog: changelog,
        downloadUrl: downloadUrl,
        publishedAt: publishedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String latest, String current) {
    final l = _parse(latest);
    final c = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final parts = v
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^\d]'), '')) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}
