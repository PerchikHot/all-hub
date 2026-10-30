import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'media_browser_page.dart';
import 'media_feed_query.dart';

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
  int emptyPageRetries = 0;
  int fetchedPosts = 0;
  int filteredPosts = 0;
  String kind = 'all';
  bool showFuta = true;
  bool showTrans = true;
  static const feedTags = <String>['futanari', 'transgender'];
  static const maxVisiblePosts = 180;
  final seenPostIds = <String>{};
  static const maxImageCacheBytes = 80 * 1024 * 1024;
  String error = '';
  bool accessDenied = false;
  String activeQuery = '';
  static const int pageSize = 100;
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

  Future<void> search() async {
    final q = queryController.text.trim();
    searchGeneration++;
    setState(() {
      activeQuery = q.isEmpty ? '' : (aliases[q.toLowerCase()] ?? q.replaceAll(RegExp(r'\s+'), '_'));
      posts.clear();
      seenPostIds.clear();
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
    if (loading || !hasMore) return;
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
      final selectedTag = enabledTags[(requestedPage - 1) % enabledTags.length];
      final sourcePage = ((requestedPage - 1) ~/ enabledTags.length) + 1;
      // Search all ratings: forcing rating:explicit hid valid tagged posts.
      final tags = requestedKind == 'gif' && requestedQuery.isEmpty
          ? '$selectedTag filetype:gif'
          : buildMediaFeedTags(selectedTag, requestedQuery);
      final uri = Uri.https('danbooru.donmai.us', '/posts.json', {
        'tags': tags,
        'limit': '$pageSize',
        'page': '$sourcePage',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
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
      final newPosts = data.whereType<Map<String, dynamic>>().where((p) =>
          isVisibleFeedPost(p, selectedTag: selectedTag,
              kind: requestedKind, seenIds: seenPostIds)).toList();
      setState(() {
        fetchedPosts += data.length;
        filteredPosts += data.length - newPosts.length;
        for (final post in newPosts) {
          seenPostIds.add((post['id'] ?? '').toString());
        }
        posts.addAll(newPosts);
        emptyPageRetries = newPosts.isEmpty ? emptyPageRetries + 1 : 0;
        if (posts.length > maxVisiblePosts) {
          posts.removeRange(0, posts.length - maxVisiblePosts);
        }
        page++;
        // Sparse GIF results can require scanning several source pages.
        // Never report an empty search while another page can still be checked.
        hasMore = shouldContinueMediaFeed(
          fetched: data.length, pageSize: pageSize,
          categoryCount: enabledTags.length, requestedPage: requestedPage,
          emptyRetries: emptyPageRetries, hasPosts: posts.isNotEmpty,
        );
      });
    } catch (e) {
      if (mounted && generation == searchGeneration) {
        setState(() {
          accessDenied = e is _FeedAccessDenied;
          error = accessDenied
              ? 'Источник отклонил запрос (HTTP 403). Проверь доступ или открой поиск на сайте.'
              : e is _FeedRateLimited
                  ? 'Источник временно ограничил запросы (HTTP 429). Попробуй позже.'
                  : 'Не удалось загрузить изображения: $e';
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
            onSelected: (value) { showFuta = value; search(); },
          ),
          FilterChip(
            label: const Text('Трансы'),
            selected: showTrans,
            onSelected: (value) { showTrans = value; search(); },
          ),
          FilterChip(
            label: const Text('Без обрезки'),
            tooltip: 'Показать изображение целиком, сохранив пропорции',
            selected: showEntireImage,
            onSelected: (value) => setState(() => showEntireImage = value),
          ),
        ]),
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
    if (posts.isNotEmpty) Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('Загружено изображений: ${posts.length}',
          style: const TextStyle(color: Colors.white70)),
      ),
    ),
    if (!showFuta && !showTrans) const Padding(
      padding: EdgeInsets.all(8), child: Text('Включи «Футы» или «Трансы» для поиска.'),
    ),
    if (!loading && !hasMore && posts.isEmpty && error.isEmpty && (showFuta || showTrans)) Padding(
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
          // Use a sharper sample for HD; thumbnails are only placeholders.
          final url = mediaFeedImageUrl(post, highQuality: highQuality) ?? '';
          return InkWell(
            onTap: () => openPost(post),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url, fit: showEntireImage ? BoxFit.contain : BoxFit.cover,
                filterQuality: FilterQuality.medium,
                cacheWidth: highQuality ? 900 : 420,
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
