import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Render direct photos and animated GIFs with Flutter on both platforms.
/// Android WebView navigation can treat a GIF as a download instead of showing
/// it. A native Image widget also supports pinch-to-zoom and explicit saving.
bool isDirectImageMediaUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp']
        .any(uri.path.toLowerCase().endsWith);

Future<void> migrateAllHubMedia() => MediaBrowserPage.migrateLegacyMedia();

class MediaBrowserPage extends StatefulWidget {
  const MediaBrowserPage({super.key, required this.url});
  final Uri url;

  static bool _migrationStarted = false;
  static Future<void> migrateLegacyMedia() async {
    if (_migrationStarted || !Platform.isAndroid) return;
    _migrationStarted = true;
    try {
      final external = await getExternalStorageDirectory();
      final documents = await getApplicationDocumentsDirectory();
      final folders = <Directory>[
        if (external != null) Directory('${external.path}/AllHubMedia'),
        Directory('${documents.path}/AllHubMedia'),
      ];
      for (final folder in folders) {
        if (!await folder.exists()) continue;
        await for (final entry in folder.list()) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.last;
          if (!RegExp(r'\.(jpg|jpeg|png|webp|gif|mp4|webm|mov)$', caseSensitive: false).hasMatch(name)) continue;
          try {
            await const MethodChannel('allhub/launcher').invokeMethod<String>(
              'saveMediaToDownloads', {'path': entry.path, 'name': name});
            await entry.delete();
          } catch (_) { /* Preserve file on failure. */ }
        }
      }
    } catch (_) {}
  }

  @override
  State<MediaBrowserPage> createState() => _MediaBrowserPageState();
}

class _MediaBrowserPageState extends State<MediaBrowserPage> {
  WebViewController? browser;
  String currentUrl = '';
  bool loading = true;
  bool downloading = false;
  String? pageError;
  String? savedFile;


  /// Flutter can render still images and animated GIFs on Windows without
  /// handing private browsing to an external application.
  bool isDirectImage(Uri uri) => isDirectImageMediaUri(uri);

  bool isMedia(Uri uri) {
    final path = uri.path.toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.mp4', '.webm', '.mov']
        .any(path.endsWith);
  }

  @override
  void initState() {
    super.initState();
    currentUrl = widget.url.toString();
    // Direct images/GIFs should open inside the app, never auto-download
    // through Android WebView's navigation delegate.
    if (isDirectImage(widget.url)) {
      loading = false;
      return;
    }
    if (!Platform.isAndroid) loading = false;
    if (Platform.isAndroid) {
      browser = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { currentUrl = url; loading = true; pageError = null; });
          },
          onPageFinished: (url) {
            if (mounted) setState(() { currentUrl = url; loading = false; });
          },
          onWebResourceError: (error) {
            // A failed image or ad must not hide an otherwise working page.
            if (!mounted || error.isForMainFrame != true) return;
            setState(() {
              loading = false;
              pageError = 'Страница недоступна. Проверь подключение и повтори загрузку.';
            });
          },

        ))
        ..loadRequest(widget.url);
    }
  }

  Future<void> download(Uri uri) async {
    if (downloading || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    setState(() => downloading = true);
    http.Client? client;
    File? temp;
    try {
      client = http.Client();
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final type = response.headers['content-type']?.toLowerCase() ?? '';
      if (!(type.startsWith('image/') || type.startsWith('video/') ||
          type.startsWith('application/octet-stream'))) {
        throw Exception('Ссылка не ведёт на изображение или видео');
      }
      // Temporary private staging only. Final media is written to public Downloads/All Hub.
      final folder = await getTemporaryDirectory();
      final ext = switch (type.split(';').first) {
        'image/gif' => '.gif',
        'image/png' => '.png',
        'image/webp' => '.webp',
        'image/jpeg' => '.jpg',
        'video/mp4' => '.mp4',
        'video/webm' => '.webm',
        _ => '.bin',
      };
      final raw = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final name = raw.contains('.') ? raw : 'media$ext';
      final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final destination = File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}_$safe');
      temp = File('${destination.path}.part');
      final sink = temp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          if (received > 200 * 1024 * 1024) {
            throw Exception('Файл больше 200 МБ');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temp.rename(destination.path);
      temp = null;
      String finalPath;
      try {
        if (Platform.isAndroid) {
          finalPath = await const MethodChannel('allhub/launcher').invokeMethod<String>(
            'saveMediaToDownloads', {'path': destination.path, 'name': destination.uri.pathSegments.last})
              ?? 'Downloads/All Hub';
        } else {
          final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
          if (home == null) throw StateError('Папка пользователя не найдена');
          final downloads = Directory('$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}All Hub');
          await downloads.create(recursive: true);
          final target = File('${downloads.path}${Platform.pathSeparator}${destination.uri.pathSegments.last}');
          await destination.copy(target.path);
          finalPath = target.path;
        }
      } finally {
        if (await destination.exists()) await destination.delete();
      }
      if (mounted) {
        setState(() => savedFile = finalPath);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено: $finalPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось скачать: $e')),
        );
      }
    } finally {
      client?.close();
      if (temp != null && await temp.exists()) await temp.delete();
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> saveCurrent() async {
    final uri = Uri.tryParse(currentUrl);
    if (uri == null || !isMedia(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Открой прямую ссылку на фото, GIF или видео для скачивания'),
      ));
      return;
    }
    await download(uri);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Медиа • All Hub'),
      actions: [
        IconButton(
          tooltip: 'Назад по страницам',
          onPressed: browser == null ? null : () async {
            if (await browser!.canGoBack()) await browser!.goBack();
          },
          icon: const Icon(Icons.arrow_back),
        ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: browser == null ? null : () => browser!.reload(),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Скачать открытый файл',
          onPressed: downloading ? null : saveCurrent,
          icon: const Icon(Icons.download),
        ),
      ],
    ),
    body: Column(children: [
      if (loading || downloading) const LinearProgressIndicator(),
      if (pageError != null)
        MaterialBanner(
          content: Text(pageError!),
          actions: [TextButton(
            onPressed: browser == null ? null : () {
              setState(() { pageError = null; loading = true; });
              browser!.reload();
            },
            child: const Text('Повторить'),
          )],
        ),
      if (savedFile != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(
          'Последний файл: $savedFile', maxLines: 2, overflow: TextOverflow.ellipsis)),
      Expanded(child: browser != null
          ? WebViewWidget(controller: browser!)
          : isDirectImage(widget.url)
              ? ClipRect(child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6,
                  child: Center(child: Image.network(
                    widget.url.toString(),
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : Center(child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes == null ? null
                                : progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!,
                          )),
                    errorBuilder: (context, error, stackTrace) =>
                        const Center(child: Text(
                          'Изображение недоступно. Проверь ссылку или соединение.',
                        )),
                  )),
                ))
              : Center(child: FilledButton(
                  onPressed: () => launchUrl(widget.url,
                    mode: LaunchMode.externalApplication),
                  child: const Text('Открыть страницу в системном браузере'),
                ))),
    ]),
  );
}
