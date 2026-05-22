import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';
import 'apk_installer.dart';
import 'update_service.dart';

/// Shows a modal bottom sheet with release info.
/// Safe to call when no update is available — does nothing in that case.
Future<void> showUpdateDialog(
  BuildContext context,
  ReleaseInfo release,
) async {
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _UpdateSheet(release: release),
  );
}

class _UpdateSheet extends StatefulWidget {
  final ReleaseInfo release;

  const _UpdateSheet({required this.release});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  // null = idle, 0..1 = downloading, -1 = error
  double? _progress;

  Future<void> _startDownload() async {
    setState(() => _progress = 0.0);

    final httpClient = io.HttpClient();
    try {
      final rq = await httpClient.getUrl(Uri.parse(widget.release.downloadUrl));
      rq.headers.set('Accept', 'application/octet-stream');
      // dart:io HttpClient follows redirects automatically (maxRedirects = 5)
      final rs = await rq.close();

      if (rs.statusCode != 200) {
        if (mounted) setState(() => _progress = null);
        return;
      }

      final total = rs.contentLength; // -1 if unknown
      var received = 0;

      final dir = await _apkDirectory();
      final file = io.File('${dir.path}/hookah_admin_update.apk');
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();

      await for (final chunk in rs) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      }

      await sink.flush();
      await sink.close();

      if (!mounted) return;
      await ApkInstaller.install(file.path);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _progress = -1);
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<io.Directory> _apkDirectory() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    } catch (_) {}
    return getTemporaryDirectory();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');
    final changelog = widget.release.changelog.trim();
    final isDownloading = _progress != null && _progress! >= 0;
    final isError = _progress == -1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    widget.release.tagName,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Доступно обновление',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              df.format(widget.release.publishedAt),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),

            if (changelog.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Что нового:',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    changelog,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Progress bar
            if (isDownloading && _progress! >= 0 && _progress! < 1) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.gold),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress! * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],

            if (isError) ...[
              const Text(
                'Ошибка загрузки. Попробуйте снова.',
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isDownloading && !isError
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.muted,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Позже'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isDownloading && !isError ? null : _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      disabledBackgroundColor:
                          AppColors.gold.withValues(alpha: 0.5),
                    ),
                    child: Text(
                      isError
                          ? 'Повторить'
                          : isDownloading
                              ? 'Загрузка...'
                              : 'Скачать и установить',
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
