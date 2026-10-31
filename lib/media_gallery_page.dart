import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'media_browser_page.dart';
import 'media_feed_query.dart';
import 'media_favorites.dart';
import 'multi_engine_search_page.dart';

class MediaGalleryPage extends StatefulWidget {
  const MediaGalleryPage({super.key});
  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  final queryController = TextEditingController();
  final scroll = ScrollController();
  final posts = <Map<String, dynamic>>[];
  final favoritePosts = <Map<String, dynamic>>[];
  final favoriteIds = <String>{};
  bool favoritesOnly = false;
  List<Map<String, dynamic>> get visiblePosts => favoritesOnly ? favoritePosts : posts;
  bool loading = false;
  bool hasMore = true;
  int page = 1;
  int emptyPageRetries = 0;
  int fetchedPosts = 0;
  int filteredPosts = 0;
  String kind = 'all';
  bool showFuta = true;
  bool showTrans = true;
  static const feedTags = <String>['futanari', 'transgender'];
  static const maxVisiblePosts = 180;
  final seenPostIds = <String>{};
  final seenPostUrls = <String>{};
  final exhaustedFeedTags = <String>{};
  static const maxImageCacheBytes = 80 * 1024 * 1024;
  String error = '';
  bool accessDenied = false;
  String activeQuery = '';
  static const int pageSize = 40;
  bool highQuality = true;
  bool showEntireImage = false;
  int searchGeneration = 0;
  static const aliases = <String, String>{
    'аква': 'aqua_(konosuba)',
    'эрза': 'erza_scarlet',
    'темари': 'temari_(naruto)',
    'тен тен': 'tenten_(naruto)',
    'акира': 'aira_shiratori',
    'шуга': 'shuna_(tensei_shitara_slime_datta_ken)',
    'шина': 'shion_(tensei_shitara_slime_datta_ken)',
    'даркнес': 'darkness_(konosuba)',
    'юно': 'gasai_yuno',
    'нами': 'nami_(one_piece)',
    'рукия': 'kuchiki_rukia',
    'ребекка': 'rebecca_(cyberpunk)',
    'орихиме': 'inoue_orihime',
    'ноэль': 'noelle_silva',
    'аска': 'souryuu_asuka_langley',
    'алиса сао': 'alice_zuberg',
    'хината': 'hyuuga_hinata',
    'боа': 'boa_hancock',
    'незуко': 'kamado_nezuko',
    'ноль два': 'zero_two_(darling_in_the_franxx)',
    'нобара': 'kugisaki_nobara',
    'митсури': 'kanroji_mitsuri',
    'ямато': 'yamato_(one_piece)',
    'эсил': 'esil_radiru',
    'шинобу': 'kochou_shinobu',
    'мимоза': 'mimosa_vermillion',
    'рафталия': 'raphtalia',
    'момо': 'ayase_momo',
    'асуна': 'yuuki_asuna',
    'нелиэл': 'neliel_tu_odelschwanck',
    'альбедо': 'albedo_(overlord)',
    'рем': 'rem_(re_zero)',
    'рам': 'ram_(re_zero)',
    'эмилия': 'emilia_(re_zero)',
    'алиса михайловна': 'kujou_alisa_mikhailovna',
    'риас': 'rias_gremory',
    'эсдес': 'esdeath',
    'чха хе ин': 'cha_haein',
    'сейко': 'ayase_seiko',
    'ферн': 'fern_(sousou_no_frieren)',
    'марин': 'kitagawa_marin',
    'урарака': 'uraraka_ochako',
    'йор': 'yor_forger',
    'тору хагакуре': 'hagakure_tooru',
    'фрирен': 'frieren',
    'макима': 'makima_(chainsaw_man)',
    'акено': 'himejima_akeno',
    'коми': 'komi_shouko',
    'мать коми': 'komi_shuuko',
    'яойорозу': 'yaoyorozu_momo',
    'тсую': 'asui_tsuyu',
    'пинки': 'ashido_mina',
    'леди гора': 'mt._lady',
    'полночь': 'midnight_(boku_no_hero_academia)',
    'мегумин': 'megumin',
    'цунаде': 'tsunade',
    'сарада': 'uchiha_sarada',
    'сестра хинаты': 'hyuuga_hanabi',
    'сакура': 'haruno_sakura',
    'ху тао': 'hu_tao_(genshin_impact)',
    'конеко': 'toujou_koneko',
    'удзаки': 'uzaki_hana',
    'мать удзаки': 'uzaki_tsuki',
    'люси': 'lucy_heartfilia',
    'миражанна': 'mirajane_strauss',
    'мируко': 'usagiyama_rumi',
    'даки': 'daki_(kimetsu_no_yaiba)',
    'кушина': 'uzumaki_kushina',
    'альфа': 'alpha_(kage_no_jitsuryokusha)',
    'дельта': 'delta_(kage_no_jitsuryokusha)',
    'томоэ': 'tomoe_(tsuki_ga_michibiku_isekai_douchuu)',
    'йошино': 'yoshino_(date_a_live)',
    'куруми': 'tokisaki_kurumi',
    'котори': 'itsuka_kotori',
    'тохка': 'yatogami_tohka',
    'оригами': 'tobiichi_origami',
    'мику': 'izayoi_miku',
    'нацуми': 'kyouno_natsumi',
    'ния': 'honjou_nia',
    'мукуро': 'hoshimiya_mukuro',
    'шидо сестра': 'itsuka_kotori',
    'лилит': 'lilith_asami',
    'арин': 'arin_kannazuki',
    'юи': 'yui_kurata',
    'мира': 'mira_yamana',
    'леви': 'levi_kazama',
    'акио': 'akio_fudou',
    'лизелотта': 'lieselotte_sherlock',
    'бета': 'beta_(kage_no_jitsuryokusha)',
    'гамма': 'gamma_(kage_no_jitsuryokusha)',
    'эпсилон': 'epsilon_(kage_no_jitsuryokusha)',
    'дзета': 'zeta_(kage_no_jitsuryokusha)',
    'эта': 'eta_(kage_no_jitsuryokusha)',
    'эрза скарлет': 'erza_scarlet',
    'тентен': 'tenten_(naruto)',
    'айра': 'aira_shiratori',
    'шунa': 'shuna_(tensei_shitara_slime_datta_ken)',
    'шуна': 'shuna_(tensei_shitara_slime_datta_ken)',
    'шион': 'shion_(tensei_shitara_slime_datta_ken)',
    'даркнесс': 'darkness_(konosuba)',
    'юно гасай': 'gasai_yuno',
    'ноль-два': 'zero_two_(darling_in_the_franxx)',
    'марин китагава': 'kitagawa_marin',
    'риас гремори': 'rias_gremory',
    'асуна сао': 'yuuki_asuna',
    'акено химэдзима': 'himejima_akeno',
    'мимоза вермилион': 'mimosa_vermillion',
    'мегумин коносуба': 'megumin',
    'ёшино': 'yoshino_(date_a_live)',
    'йосино': 'yoshino_(date_a_live)',
    'йосинон': 'yoshino_(date_a_live)',
    'тсунале': 'tsunade',
    'яуярозу': 'yaoyorozu_momo',
    'шинон': 'shion_(tensei_shitara_slime_datta_ken)',
  };

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.maximumSizeBytes = maxImageCacheBytes;
    scroll.addListener(() {
      if (!favoritesOnly && scroll.hasClients && scroll.position.extentAfter < 700 && !loading && hasMore) {
        loadMore();
      }
    });
    _restoreFeedPreferences();
  }

  // Preserve feed filters and image display choices between app launches.
  // Search results and private queries are deliberately not persisted.
  Future<void> _restoreFeedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        showFuta = prefs.getBool('media_show_futa_v1') ?? true;
        showTrans = prefs.getBool('media_show_trans_v1') ?? true;
        highQuality = prefs.getBool('media_hd_v1') ?? true;
        showEntireImage = prefs.getBool('media_fit_v1') ?? false;
        kind = prefs.getString('media_kind_v1') == 'gif' ? 'gif' : 'all';
        favoritePosts
          ..clear()
          ..addAll(readMediaFavorites(prefs.getString('media_favorites_v1')));
        favoriteIds
          ..clear()
          ..addAll(favoritePosts.map((post) => post['id'].toString()));
      });
    } catch (_) {
      // Storage may be unavailable; default filters still work offline.
    }
    if (mounted) await search();
  }

  Future<void> _saveFeedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('media_show_futa_v1', showFuta);
      await prefs.setBool('media_show_trans_v1', showTrans);
      await prefs.setBool('media_hd_v1', highQuality);
      await prefs.setBool('media_fit_v1', showEntireImage);
      await prefs.setString('media_kind_v1', kind);
    } catch (_) {
      // Never block browsing because preferences could not be written.
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> source) async {
    final safe = safeMediaFavorite(source);
    if (safe == null) return;
    final id = safe['id'] as String;
    setState(() {
      if (favoriteIds.remove(id)) {
        favoritePosts.removeWhere((post) => post['id'] == id);
      } else {
        favoritePosts.insert(0, safe);
        favoriteIds.add(id);
        if (favoritePosts.length > maxMediaFavorites) {
          final removed = favoritePosts.removeLast();
          favoriteIds.remove(removed['id']);
        }
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('media_favorites_v1',
        writeMediaFavorites(favoritePosts));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить избранное на устройстве')));
      }
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    queryController.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final q = queryController.text.trim();
    favoritesOnly = false;
    searchGeneration++;
    setState(() {
      activeQuery = q.isEmpty ? '' : (aliases[q.toLowerCase()] ?? q.replaceAll(RegExp(r'\s+'), '_'));
      posts.clear();
      seenPostIds.clear();
      seenPostUrls.clear();
      exhaustedFeedTags.clear();
      page = 1;
      emptyPageRetries = 0;
      fetchedPosts = 0;
      filteredPosts = 0;
      hasMore = true;
      error = '';
      accessDenied = false;
    });
    loading = false;
    // Keep pull-to-refresh active until the first network response arrives.
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore || favoritesOnly) return;
    setState(() => loading = true);
    final generation = searchGeneration;
    final requestedPage = page;
    final requestedQuery = activeQuery;
    final requestedKind = kind;
    final requestedFuta = showFuta;
    final requestedTrans = showTrans;
    if (!requestedFuta && !requestedTrans) {
      setState(() { loading = false; hasMore = false; });
      return;
    }
    try {
      // Combine enabled categories into one feed, alternating their pages.
      // Keep the public two-tag search limit: category + rating, or
      // category + the user's query (rating then checked locally).
      final enabledTags = <String>[
        if (requestedFuta) feedTags[0],
        if (requestedTrans) feedTags[1],
      ];
      final effectivePage = nextAvailableMediaFeedPage(
          requestedPage, enabledTags, exhaustedFeedTags);
      if (effectivePage == null) {
        if (mounted && generation == searchGeneration) {
          setState(() => hasMore = false);
        }
        return;
      }
      final selectedTag = enabledTags[(effectivePage - 1) % enabledTags.length];
      final sourcePage = ((effectivePage - 1) ~/ enabledTags.length) + 1;
      // Search all ratings: forcing rating:explicit hid valid tagged posts.
      final tags = buildMediaFeedRequestTags(
          selectedTag, requestedQuery, requestedKind);
      final uri = Uri.https('danbooru.donmai.us', '/posts.json', {
        'tags': tags,
        'limit': '$pageSize',
        'page': '$sourcePage',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 18));
      if (response.statusCode == 403) {
        throw const _FeedAccessDenied();
      }
      if (response.statusCode == 429) {
        throw const _FeedRateLimited();
      }
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data is! List) throw const FormatException('Неверный ответ сервера');
      if (!mounted || generation != searchGeneration || requestedQuery != activeQuery || requestedKind != kind || requestedFuta != showFuta || requestedTrans != showTrans) return;
      // The API can repeat an ID inside one response. De-duplicate before
      // rendering, not only after merging the page into seenPostIds.
      final newPosts = filterNewMediaFeedPosts(
        data.whereType<Map<String, dynamic>>(),
        selectedTag: selectedTag, kind: requestedKind,
        seenIds: seenPostIds, seenUrls: seenPostUrls,
        query: requestedQuery,
      );
      setState(() {
        fetchedPosts += data.length;
        filteredPosts += data.length - newPosts.length;
        for (final post in newPosts) {
          seenPostIds.add((post['id'] ?? '').toString());
          final thumbnail = mediaFeedImageUrl(post, highQuality: false);
          if (thumbnail != null) seenPostUrls.add(thumbnail);
        }
        posts.addAll(newPosts);
        emptyPageRetries = newPosts.isEmpty ? emptyPageRetries + 1 : 0;
        if (posts.length > maxVisiblePosts) {
          posts.removeRange(0, posts.length - maxVisiblePosts);
        }
        // One sparse category must not stop another category's pagination.
        if (data.length < pageSize) exhaustedFeedTags.add(selectedTag);
        page = effectivePage + 1;
        hasMore = emptyPageRetries < 8 &&
            nextAvailableMediaFeedPage(
                page, enabledTags, exhaustedFeedTags) != null;
      });
    } catch (e) {
      if (mounted && generation == searchGeneration) {
        setState(() {
          accessDenied = e is _FeedAccessDenied;
          error = accessDenied
              ? 'Источник отклонил запрос (HTTP 403). Проверь доступ или открой поиск на сайте.'
              : e is _FeedRateLimited
                  ? 'Источник временно ограничил запросы (HTTP 429). Попробуй позже.'
                  : 'Не удалось подключиться к источнику. Проверь сеть или открой Яндекс.Картинки.';
          hasMore = false;
        });
      }
    } finally {
      if (mounted && generation == searchGeneration) {
        setState(() => loading = false);
        // GIFs are sparse: continue scanning a few pages before showing an
        // empty gallery. Also try the other enabled category automatically.
        if (error.isEmpty && hasMore && posts.isEmpty &&
            emptyPageRetries < 12 && (showFuta || showTrans)) {
          Future.microtask(() => loadMore());
        }
      }
    }
  }

  // A failed next page should not discard images already loaded into the feed.
  Future<void> retryFailedPage() async {
    if (loading || posts.isEmpty) return;
    setState(() {
      error = '';
      accessDenied = false;
      hasMore = true;
    });
    await loadMore();
  }

  Future<void> openYandexSearch() async {
    final query = <String>[
      if (showFuta) 'futanari',
      if (showTrans) 'transgender',
      if (activeQuery.isNotEmpty) activeQuery.replaceAll('_', ' '),
    ].join(' ');
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MultiEngineSearchPage(
        query: query.isEmpty ? 'anime art' : query,
        media: kind == 'gif' ? 'gifs' : 'images',
      ),
    ));
  }

  Future<void> openSourceSearch() async {
    final tags = <String>[
      if (showFuta) feedTags[0],
      if (showTrans && !showFuta) feedTags[1],
      if (activeQuery.isNotEmpty) activeQuery,
    ].join(' ');
    final uri = Uri.https('danbooru.donmai.us', '/posts', {'tags': tags});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть сайт источника')),
      );
    }
  }

  void openPost(Map<String, dynamic> post) {
    final raw = mediaFeedImageUrl(post, highQuality: true);
    final uri = raw == null ? null : Uri.tryParse(raw);
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
        Wrap(spacing: 8, runSpacing: 4, children: [
          FilterChip(
            label: const Text('Футы'),
            selected: showFuta,
            onSelected: (value) { showFuta = value; _saveFeedPreferences(); search(); },
          ),
          FilterChip(
            label: const Text('Трансы'),
            selected: showTrans,
            onSelected: (value) { showTrans = value; _saveFeedPreferences(); search(); },
          ),
          FilterChip(
            label: Text('Избранное (${favoritePosts.length})'),
            selected: favoritesOnly,
            onSelected: (value) {
              setState(() => favoritesOnly = value);
              if (!value && posts.isEmpty && !loading) search();
            },
          ),
          FilterChip(
            label: const Text('Без обрезки'),
            tooltip: 'Показать изображение целиком, сохранив пропорции',
            selected: showEntireImage,
            onSelected: (value) { setState(() => showEntireImage = value); _saveFeedPreferences(); },
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(label: const Text('Картинки'), selected: kind == 'all', onSelected: (_) {
            setState(() => kind = 'all');
            _saveFeedPreferences();
            search();
          }),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('GIF'), selected: kind == 'gif', onSelected: (_) {
            setState(() => kind = 'gif');
            _saveFeedPreferences();
            search();
          }),
          const Spacer(),
          const Text('HD'),
          Switch.adaptive(value: highQuality, onChanged: (value) { setState(() => highQuality = value); _saveFeedPreferences(); }),
          IconButton(tooltip: 'Обновить', onPressed: search, icon: const Icon(Icons.refresh)),
        ]),
      ]),
    ),
    if (loading && posts.isEmpty && (showFuta || showTrans)) Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'Проверяем источник: страница $page · получено $fetchedPosts записей',
          style: const TextStyle(color: Colors.white70),
        )),
      ]),
    ),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: openYandexSearch,
        icon: const Icon(Icons.travel_explore),
        label: Text('Яндекс.Картинки • ${kind == 'gif' ? 'GIF' : 'изображения'}'),
      )),
    ),
    if (error.isNotEmpty) Padding(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: posts.isEmpty ? search : retryFailedPage, icon: const Icon(Icons.refresh), label: Text(posts.isEmpty ? 'Повторить' : 'Повторить страницу')),
          OutlinedButton.icon(
            onPressed: openSourceSearch,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Открыть поиск на сайте')),
        ]),
      ]),
    ),
    if (visiblePosts.isNotEmpty) Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(favoritesOnly
          ? 'Сохранено в избранном: ${favoritePosts.length} (локально)'
          : 'Загружено изображений: ${posts.length}',
          style: const TextStyle(color: Colors.white70)),
      ),
    ),
    if (favoritesOnly && favoritePosts.isEmpty)
      const Padding(padding: EdgeInsets.all(12),
        child: Text('Пока нет избранного. Нажми сердечко на изображении, чтобы сохранить его здесь.')),
    if (!favoritesOnly && !showFuta && !showTrans) const Padding(
      padding: EdgeInsets.all(8), child: Text('Включи «Футы» или «Трансы» для поиска.'),
    ),
    if (!favoritesOnly && !loading && !hasMore && posts.isEmpty && error.isEmpty && (showFuta || showTrans)) Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        const Text('Источник не вернул подходящих изображений. Попробуй другой тег или проверь поиск на сайте.'),
        if (fetchedPosts > 0) Text('Получено записей: $fetchedPosts, исключено фильтрами: $filteredPosts'),
        TextButton.icon(
          onPressed: openSourceSearch,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Открыть поиск на сайте'),
        ),
      ]),
    ),
    Expanded(child: RefreshIndicator(
      onRefresh: search,
      child: MasonryGridView.builder(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(6),
        gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
        ),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        itemCount: visiblePosts.length + (!favoritesOnly && loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visiblePosts.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final post = visiblePosts[index];
          final id = (post['id'] ?? '').toString();
          return AspectRatio(
            aspectRatio: mediaFeedTileAspectRatio(post),
            child: Stack(children: [
              Positioned.fill(child: InkWell(
                onTap: () => openPost(post),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _FeedFallbackImage(
                    key: ValueKey('feed-$id-$highQuality'),
                    post: post,
                    highQuality: highQuality,
                    fit: showEntireImage ? BoxFit.contain : BoxFit.cover,
                  ),
                ),
              )),
              if (mediaFeedAnimatedUrl(post) != null)
                Positioned(left: 6, top: 6, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xD9101B32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_circle_outline, size: 14, color: Colors.white),
                    SizedBox(width: 3),
                    Text('GIF', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold,
                      fontSize: 11)),
                  ]),
                )),
              Positioned(right: 3, top: 3, child: IconButton(
                tooltip: favoriteIds.contains(id) ? 'Убрать из избранного' : 'В избранное',
                icon: Icon(favoriteIds.contains(id)
                  ? Icons.favorite : Icons.favorite_border,
                  color: favoriteIds.contains(id)
                    ? const Color(0xFFFF6F9F) : Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xBB0A1426)),
                onPressed: () => _toggleFavorite(post),
              )),
            ]),
          );
        },
      ),
    )),
  ]);
}

/// Retry the next CDN asset only after an image request fails. This is
/// bounded by the four URLs supplied by the post, never an infinite retry loop.
class _FeedFallbackImage extends StatefulWidget {
  const _FeedFallbackImage({
    super.key,
    required this.post,
    required this.highQuality,
    required this.fit,
  });
  final Map<String, dynamic> post;
  final bool highQuality;
  final BoxFit fit;

  @override
  State<_FeedFallbackImage> createState() => _FeedFallbackImageState();
}

class _FeedFallbackImageState extends State<_FeedFallbackImage> {
  int index = 0;

  @override
  void didUpdateWidget(covariant _FeedFallbackImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post ||
        oldWidget.highQuality != widget.highQuality) {
      index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = mediaFeedImageCandidates(
      widget.post, highQuality: widget.highQuality);
    if (candidates.isEmpty) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
    final current = index < candidates.length ? index : candidates.length - 1;
    final url = candidates[current];
    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
      memCacheWidth: widget.highQuality ? 900 : 420,
      // Disk resizing decodes only one frame of some GIFs. Cache original
      // animation bytes instead, while retaining the bounded memory cache.
      maxWidthDiskCache: isAnimatedFeedAssetUrl(url)
          ? null : (widget.highQuality ? 900 : 420),
      fadeInDuration: Duration.zero,
      placeholder: (context, _) => const Center(
        child: Icon(Icons.image_outlined, color: Colors.white24)),
      errorWidget: (context, failedUrl, error) {
        if (current + 1 < candidates.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && index == current &&
                candidates[index] == failedUrl) {
              setState(() => index++);
            }
          });
          return const Center(child: Icon(
            Icons.downloading_outlined, color: Colors.white38));
        }
        return const Center(child: Icon(Icons.broken_image_outlined));
      },
    );
  }
}

class _FeedRateLimited implements Exception {
  const _FeedRateLimited();
  @override
  String toString() => 'HTTP 429 Too Many Requests';
}

class _FeedAccessDenied implements Exception {
  const _FeedAccessDenied();
  @override
  String toString() => 'HTTP 403 Forbidden';
}
