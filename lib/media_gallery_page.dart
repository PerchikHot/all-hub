import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'media_browser_page.dart';

class MediaGalleryPage extends StatefulWidget {
  const MediaGalleryPage({super.key});
  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  final queryController = TextEditingController();
  final scroll = ScrollController();
  final posts = <Map<String, dynamic>>[];
  bool loading = false;
  bool hasMore = true;
  int page = 1;
  String kind = 'all';
  String error = '';
  String activeQuery = '';
  bool highQuality = false;
  static const int pageSize = 18;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.hasClients && scroll.position.extentAfter < 700 && !loading && hasMore) {
        loadMore();
      }
    });
    search();
  }

  @override
  void dispose() {
    scroll.dispose();
    queryController.dispose();
    super.dispose();
  }

  void search() {
    final q = queryController.text.trim();
    setState(() {
      activeQuery = q.isEmpty ? 'futanari' : q.replaceAll(RegExp(r'\s+'), '_');
      posts.clear();
      page = 1;
      hasMore = true;
      error = '';
    });
    loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    setState(() => loading = true);
    final requestedPage = page;
    final requestedQuery = activeQuery;
    final requestedKind = kind;
    try {
      final tags = [requestedQuery, if (requestedKind == 'gif') 'animated_gif'].join(' ');
      final uri = Uri.https('danbooru.donmai.us', '/posts.json', {
        'tags': tags,
        'limit': '$pageSize',
        'page': '$requestedPage',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data is! List) throw const FormatException('Неверный ответ сервера');
      if (!mounted || requestedQuery != activeQuery || requestedKind != kind) return;
      final newPosts = data.whereType<Map<String, dynamic>>().where((p) {
        final preview = p['preview_file_url'] ?? p['large_file_url'] ?? p['file_url'];
        if (preview is! String || !preview.startsWith('https://')) return false;
        if (kind == 'gif') {
          final ext = (p['file_ext'] ?? '').toString().toLowerCase();
          return ext == 'gif';
        }
        return true;
      }).toList();
      setState(() {
        posts.addAll(newPosts);
        page++;
        hasMore = data.length >= pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Не удалось загрузить изображения: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void openPost(Map<String, dynamic> post) {
    final raw = post['file_url'] ?? post['large_file_url'] ?? post['preview_file_url'];
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null || uri.scheme != 'https') return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MediaBrowserPage(url: uri),
    ));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(children: [
        TextField(
          controller: queryController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => search(),
          decoration: InputDecoration(
            hintText: 'Персонаж или тег, например alpha_(kage_no_jitsuryokusha)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: search),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(label: const Text('Картинки'), selected: kind == 'all', onSelected: (_) {
            setState(() => kind = 'all');
            search();
          }),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('GIF'), selected: kind == 'gif', onSelected: (_) {
            setState(() => kind = 'gif');
            search();
          }),
          const Spacer(),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('HD при открытии'),
            Switch.adaptive(value: highQuality,
              onChanged: (v) => setState(() => highQuality = v)),
          ]),
          IconButton(tooltip: 'Обновить', onPressed: search, icon: const Icon(Icons.refresh)),
        ]),
      ]),
    ),
    if (error.isNotEmpty) Padding(
      padding: const EdgeInsets.all(8),
      child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ),
    Expanded(child: RefreshIndicator(
      onRefresh: () async { search(); },
      child: GridView.builder(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(6),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.72,
        ),
        itemCount: posts.length + (loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= posts.length) return const Center(child: CircularProgressIndicator());
          final post = posts[index];
          final url = (post['preview_file_url'] ?? post['large_file_url'] ?? post['file_url']).toString();
          return InkWell(
            onTap: () => openPost(post),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url, fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                cacheWidth: 440,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined)),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child : const Center(child: Icon(Icons.image_outlined, color: Colors.white24)),
              ),
            ),
          );
        },
      ),
    )),
  ]);
}
