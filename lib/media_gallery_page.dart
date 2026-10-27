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
  String category = 'characters';
  static const categoryTags = <String, String>{
    'characters': '',
    'solo': 'solo',
    'lesbian': 'yuri',
    'futanari': 'futanari',
  };
  static const maxVisiblePosts = 90;
  static const maxImageCacheBytes = 80 * 1024 * 1024;
  String error = '';
  String activeQuery = '';
  static const int pageSize = 24;
  bool highQuality = true;
  int searchGeneration = 0;
  // Curated characters from the user's full list; general character artwork only.
  static const favoriteTags = <String>[
    'aqua_(konosuba)',
    'erza_scarlet',
    'temari_(naruto)',
    'tenten_(naruto)',
    'aira_shiratori',
    'shuna_(tensei_shitara_slime_datta_ken)',
    'shion_(tensei_shitara_slime_datta_ken)',
    'darkness_(konosuba)',
    'gasai_yuno',
    'nami_(one_piece)',
    'kuchiki_rukia',
    'rebecca_(cyberpunk)',
    'inoue_orihime',
    'noelle_silva',
    'souryuu_asuka_langley',
    'alice_zuberg',
    'hyuuga_hinata',
    'boa_hancock',
    'kamado_nezuko',
    'zero_two_(darling_in_the_franxx)',
    'kugisaki_nobara',
    'kanroji_mitsuri',
    'yamato_(one_piece)',
    'esil_radiru',
    'kochou_shinobu',
    'mimosa_vermillion',
    'raphtalia',
    'ayase_momo',
    'yuuki_asuna',
    'neliel_tu_odelschwanck',
    'albedo_(overlord)',
    'rem_(re_zero)',
    'ram_(re_zero)',
    'emilia_(re_zero)',
    'kujou_alisa_mikhailovna',
    'rias_gremory',
    'esdeath',
    'cha_haein',
    'ayase_seiko',
    'fern_(sousou_no_frieren)',
    'kitagawa_marin',
    'uraraka_ochako',
    'yor_forger',
    'hagakure_tooru',
    'frieren',
    'makima_(chainsaw_man)',
    'himejima_akeno',
    'komi_shouko',
    'komi_shuuko',
    'yaoyorozu_momo',
    'asui_tsuyu',
    'ashido_mina',
    'mt._lady',
    'midnight_(boku_no_hero_academia)',
    'megumin',
    'tsunade',
    'uchiha_sarada',
    'hyuuga_hanabi',
    'haruno_sakura',
    'hu_tao_(genshin_impact)',
    'toujou_koneko',
    'uzaki_hana',
    'uzaki_tsuki',
    'lucy_heartfilia',
    'mirajane_strauss',
    'usagiyama_rumi',
    'daki_(kimetsu_no_yaiba)',
    'uzumaki_kushina',
    'alpha_(kage_no_jitsuryokusha)',
    'delta_(kage_no_jitsuryokusha)',
    'tomoe_(tsuki_ga_michibiku_isekai_douchuu)',
    'yoshino_(date_a_live)',
    'tokisaki_kurumi',
    'itsuka_kotori',
    'yatogami_tohka',
    'tobiichi_origami',
    'izayoi_miku',
    'kyouno_natsumi',
    'honjou_nia',
    'hoshimiya_mukuro',
    'itsuka_kotori',
    'lilith_asami',
    'arin_kannazuki',
    'yui_kurata',
    'mira_yamana',
    'levi_kazama',
    'akio_fudou',
    'lieselotte_sherlock',
    'beta_(kage_no_jitsuryokusha)',
    'gamma_(kage_no_jitsuryokusha)',
    'epsilon_(kage_no_jitsuryokusha)',
    'zeta_(kage_no_jitsuryokusha)',
    'eta_(kage_no_jitsuryokusha)',
  ];
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
    final requestedCategory = category;
    try {
      final tag = requestedQuery.isEmpty
          ? favoriteTags[(requestedPage - 1) % favoriteTags.length]
          : requestedQuery;
      final categoryTag = categoryTags[requestedCategory] ?? '';
      final tags = [tag, if (categoryTag.isNotEmpty) categoryTag,
        if (requestedKind == 'gif') 'animated_gif'].join(' ');
      final uri = Uri.https('danbooru.donmai.us', '/posts.json', {
        'tags': tags,
        'limit': '$pageSize',
        'page': '${requestedQuery.isEmpty ? 1 : requestedPage}',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data is! List) throw const FormatException('Неверный ответ сервера');
      if (!mounted || generation != searchGeneration || requestedQuery != activeQuery || requestedKind != kind || requestedCategory != category) return;
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
        if (posts.length > maxVisiblePosts) {
          posts.removeRange(0, posts.length - maxVisiblePosts);
        }
        page++;
        hasMore = requestedQuery.isEmpty ? true : data.length >= pageSize;
      });
    } catch (e) {
      if (mounted && generation == searchGeneration) {
        setState(() {
          error = 'Не удалось загрузить изображения: $e';
          hasMore = false;
        });
      }
    } finally {
      if (mounted && generation == searchGeneration) {
        setState(() => loading = false);
      }
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final option in const [
              ('characters', 'Персонажи'),
              ('solo', 'Соло'),
              ('lesbian', 'Лесби'),
              ('futanari', 'Футанари'),
            ]) ...[
              ChoiceChip(
                label: Text(option.$2),
                selected: category == option.$1,
                onSelected: (_) {
                  category = option.$1;
                  search();
                },
              ),
              const SizedBox(width: 8),
            ],
          ]),
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
          // Keep the grid lightweight even when HD is enabled. Full-size
          // files are fetched only after opening the media viewer.
          final url = (post['preview_file_url'] ??
              post['large_file_url'] ?? post['file_url']).toString();
          return InkWell(
            onTap: () => openPost(post),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url, fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                cacheWidth: 420,
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
