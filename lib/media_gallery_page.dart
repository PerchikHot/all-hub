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
  static const int pageSize = 18;
  bool highQuality = true;
  int searchGeneration = 0;
  static const favoriteTags = <String>[
    'rias_gremory', 'erza_scarlet', 'yamato_(one_piece)',
    'aqua_(konosuba)', 'darkness_(konosuba)', 'hinata_hyuga',
    'nami_(one_piece)', 'rukia_kuchiki', 'orihime_inoue',
    'noelle_silva', 'mimosa_vermillion', 'zero_two_(darling_in_the_franxx)',
    'rebecca_(cyberpunk)', 'shion_(tensei_shitara_slime_datta_ken)',
    'shuna_(tensei_shitara_slime_datta_ken)', 'alpha_(kage_no_jitsuryokusha)',
    'beta_(kage_no_jitsuryokusha)', 'mitsuri_kanroji', 'shinobu_kocho',
  ];
  static const aliases = <String, String>{
    'риас': 'rias_gremory', 'риас гремори': 'rias_gremory',
    'эрза': 'erza_scarlet', 'ямато': 'yamato_(one_piece)',
    'аква': 'aqua_(konosuba)', 'даркнесс': 'darkness_(konosuba)',
    'хината': 'hinata_hyuga', 'нами': 'nami_(one_piece)',
    'рукия': 'rukia_kuchiki', 'орихиме': 'orihime_inoue',
    'ноэль': 'noelle_silva', 'мимоза': 'mimosa_vermillion',
    'ноль два': 'zero_two_(darling_in_the_franxx)', 'ноль-два': 'zero_two_(darling_in_the_franxx)',
    'ребекка': 'rebecca_(cyberpunk)', 'шион': 'shion_(tensei_shitara_slime_datta_ken)',
    'шуна': 'shuna_(tensei_shitara_slime_datta_ken)',
    'альфа': 'alpha_(kage_no_jitsuryokusha)', 'бета': 'beta_(kage_no_jitsuryokusha)',
    'мицури': 'mitsuri_kanroji', 'шинобу': 'shinobu_kocho',
  };

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
    searchGeneration++;
    setState(() {
      activeQuery = q.isEmpty ? '' : (aliases[q.toLowerCase()] ?? q.replaceAll(RegExp(r'\s+'), '_'));
      posts.clear();
      page = 1;
      hasMore = true;
      error = '';
    });
    loading = false;
    loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    setState(() => loading = true);
    final generation = searchGeneration;
    final requestedPage = page;
    final requestedQuery = activeQuery;
    final requestedKind = kind;
    try {
      final tag = requestedQuery.isEmpty
          ? favoriteTags[(requestedPage - 1) % favoriteTags.length]
          : requestedQuery;
      final tags = [tag, if (requestedKind == 'gif') 'animated_gif'].join(' ');
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
      if (!mounted || generation != searchGeneration || requestedQuery != activeQuery || requestedKind != kind) return;
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
      if (mounted && generation == searchGeneration) setState(() => error = 'Не удалось загрузить изображения: $e');
    } finally {
      if (mounted && generation == searchGeneration) setState(() => loading = false);
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
          const Text('HD'),
          Switch.adaptive(value: highQuality, onChanged: (value) => setState(() => highQuality = value)),
          IconButton(tooltip: 'Обновить', onPressed: search, icon: const Icon(Icons.refresh)),
        ]),
      ]),
    ),
    if (error.isNotEmpty) Padding(
      padding: const EdgeInsets.all(8),
      child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ),
    if (!loading && posts.isEmpty && error.isEmpty) const Padding(
      padding: EdgeInsets.all(12), child: Text('Нет изображений по запросу. Попробуй другое имя или тег.')),
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
          final url = (highQuality
              ? (post['large_file_url'] ?? post['file_url'] ?? post['preview_file_url'])
              : (post['preview_file_url'] ?? post['large_file_url'] ?? post['file_url'])).toString();
          return InkWell(
            onTap: () => openPost(post),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url, fit: BoxFit.cover,
                filterQuality: highQuality ? FilterQuality.high : FilterQuality.low,
                cacheWidth: highQuality ? 900 : 440,
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
