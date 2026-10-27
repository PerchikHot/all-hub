import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> migrateAllHubMedia() => _MediaBrowserPageState.migrateLegacyMedia();

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
  String? savedFile;

  static const mediaChannel = MethodChannel('allhub/launcher');
  static bool migrationRunning = false;

  static Future<String> saveMedia(File file, String name) async {
    if (Platform.isAndroid) {
      return await mediaChannel.invokeMethod<String>('saveMediaToDownloads',
        {'path': file.path, 'name': name}) ?? 'Downloads/All Hub/$name';
    }
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw StateError('Не найдена домашняя папка');
    final folder = Directory('$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}All Hub');
    await folder.create(recursive: true);
    final target = File('${folder.path}${Platform.pathSeparator}$name');
    await file.copy(target.path);
    return target.path;
  }

  static Future<void> migrateLegacyMedia() async {
    if (migrationRunning || !Platform.isAndroid) return;
    migrationRunning = true;
    try {
      final external = await getExternalStorageDirectory();
      final documents = await getApplicationDocumentsDirectory();
      for (final folder in [
        if (external != null) Directory('${external.path}/AllHubMedia'),
        Directory('${documents.path}/AllHubMedia'),
      ]) {
        if (!await folder.exists()) continue;
        await for (final entry in folder.list(followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.last;
          if (!RegExp(r'^[A-Za-z0-9._-]+
    final path = uri.path.toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.mp4', '.webm', '.mov']
        .any(path.endsWith);
  }

  @override
  void initState() {
    super.initState();
    currentUrl = widget.url.toString();
    MediaBrowserPage.migrateLegacyMedia();
    migrateLegacyMedia();
    if (Platform.isAndroid) {
      browser = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { currentUrl = url; loading = true; });
          },
          onPageFinished: (url) {
            if (mounted) setState(() { currentUrl = url; loading = false; });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && isMedia(uri)) {
              download(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
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
      final directory = await getTemporaryDirectory();
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
      final filename = '${DateTime.now().microsecondsSinceEpoch}_$safe';
      final destination = File('${directory.path}/$filename');
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
      final savedPath = await saveMedia(destination, filename);
      await destination.delete();
      if (mounted) {
        setState(() => savedFile = savedPath);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено: $savedPath')),
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
      if (savedFile != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(
          'Последний файл: $savedFile', maxLines: 2, overflow: TextOverflow.ellipsis)),
      Expanded(child: browser != null
          ? WebViewWidget(controller: browser!)
          : Center(child: FilledButton(
              onPressed: () => launchUrl(widget.url, mode: LaunchMode.externalApplication),
              child: const Text('Открыть в системном браузере'),
            ))),
    ]),
  );
}
).hasMatch(name) ||
              !RegExp(r'\\.(jpg|jpeg|png|webp|gif|mp4|webm|mov)
    final path = uri.path.toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.mp4', '.webm', '.mov']
        .any(path.endsWith);
  }

  @override
  void initState() {
    super.initState();
    currentUrl = widget.url.toString();
    if (Platform.isAndroid) {
      browser = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { currentUrl = url; loading = true; });
          },
          onPageFinished: (url) {
            if (mounted) setState(() { currentUrl = url; loading = false; });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && isMedia(uri)) {
              download(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
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
      final directory = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
          await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/AllHubMedia');
      await folder.create(recursive: true);
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
      final destination = File('${folder.path}/${DateTime.now().millisecondsSinceEpoch}_$safe');
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
      if (mounted) {
        setState(() => savedFile = destination.path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено: ${destination.path}')),
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
      if (savedFile != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(
          'Последний файл: $savedFile', maxLines: 2, overflow: TextOverflow.ellipsis)),
      Expanded(child: browser != null
          ? WebViewWidget(controller: browser!)
          : Center(child: FilledButton(
              onPressed: () => launchUrl(widget.url, mode: LaunchMode.externalApplication),
              child: const Text('Открыть в системном браузере'),
            ))),
    ]),
  );
}
, caseSensitive: false).hasMatch(name)) continue;
          try {
            await saveMedia(entry, name);
            await entry.delete();
          } catch (_) {
            // Leave failed files in place for a later retry.
          }
        }
      }
    } finally {
      migrationRunning = false;
    }
  }

  bool isMedia(Uri uri) {
    final path = uri.path.toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.mp4', '.webm', '.mov']
        .any(path.endsWith);
  }

  @override
  void initState() {
    super.initState();
    currentUrl = widget.url.toString();
    if (Platform.isAndroid) {
      browser = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { currentUrl = url; loading = true; });
          },
          onPageFinished: (url) {
            if (mounted) setState(() { currentUrl = url; loading = false; });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && isMedia(uri)) {
              download(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
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
      final directory = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
          await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/AllHubMedia');
      await folder.create(recursive: true);
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
      final destination = File('${folder.path}/${DateTime.now().millisecondsSinceEpoch}_$safe');
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
      if (mounted) {
        setState(() => savedFile = destination.path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено: ${destination.path}')),
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
      if (savedFile != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(
          'Последний файл: $savedFile', maxLines: 2, overflow: TextOverflow.ellipsis)),
      Expanded(child: browser != null
          ? WebViewWidget(controller: browser!)
          : Center(child: FilledButton(
              onPressed: () => launchUrl(widget.url, mode: LaunchMode.externalApplication),
              child: const Text('Открыть в системном браузере'),
            ))),
    ]),
  );
}
