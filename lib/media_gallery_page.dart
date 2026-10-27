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
    'nelliel_tu_odelschwanck',
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
    'heartfilia_lucy',
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
    'arin_kannazuki',
    'lilith_asami',
    'levi_kazama',
    'mira_yamana',
    'akio_fudou',
    'yui_kurata',
    'lieselotte_sherlock',
    'selina_sherlock',
  ];
  static const aliases = <String, String>{
    'аква': 'aqua_(konosuba)',
    'эрза': 'erza_scarlet',
    'темари': 'temari_(naruto)',
    'тен тен': 'tenten_(naruto)',
    'акира': 'aira_shiratori',
    'шуга': 'shuna_(tensei_shitara_slime_datta_ken)',
    'шуна': 'shuna_(tensei_shitara_slime_datta_ken)',
    'шинон': 'shion_(tensei_shitara_slime_datta_ken)',
    'шион': 'shion_(tensei_shitara_slime_datta_ken)',
    'даркнес': 'darkness_(konosuba)',
    'юно': 'gasai_yuno',
    'нами': 'nami_(one_piece)',
    'рукия': 'kuchiki_rukia',
    'ребекка': 'rebecca_(cyberpunk)',
    'орихиме': 'inoue_orihime',
    'ноэль': 'noelle_silva',
    'аска': 'souryuu_asuka_langley',
    'алиса': 'alice_zuberg',
    'хината': 'hyuuga_hinata',
    'боа хенкок': 'boa_hancock',
    'незуко': 'kamado_nezuko',
    'ноль два': 'zero_two_(darling_in_the_franxx)',
    'нобара': 'kugisaki_nobara',
    'митсури': 'kanroji_mitsuri',
    'ямато': 'yamato_(one_piece)',
    'эсил': 'esil_radiru',
    'шинобу': 'kochou_shinobu',
    'мимоза': 'mimosa_vermillion',
    'рафталия': 'raphtalia',
    'момо аясе': 'ayase_momo',
    'асуна': 'yuuki_asuna',
    'нелиэл': 'nelliel_tu_odelschwanck',
    'альбедо': 'albedo_(overlord)',
    'рем': 'rem_(re_zero)',
    'рам': 'ram_(re_zero)',
    'эмилия': 'emilia_(re_zero)',
    'аля': 'kujou_alisa_mikhailovna',
    'риас': 'rias_gremory',
    'эсдес': 'esdeath',
    'чха хе ин': 'cha_haein',
    'аясе сейко': 'ayase_seiko',
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
    'яуярозу': 'yaoyorozu_momo',
    'тсую': 'asui_tsuyu',
    'пинки': 'ashido_mina',
    'леди гора': 'mt._lady',
    'полночь': 'midnight_(boku_no_hero_academia)',
    'мегумин': 'megumin',
    'тсунаде': 'tsunade',
    'сарада': 'uchiha_sarada',
    'сестра хинаты': 'hyuuga_hanabi',
    'сакура': 'haruno_sakura',
    'ху тао': 'hu_tao_(genshin_impact)',
    'конеко': 'toujou_koneko',
    'удзаки': 'uzaki_hana',
    'мать удзаки': 'uzaki_tsuki',
    'люси': 'heartfilia_lucy',
    'миражанна': 'mirajane_strauss',
    'мируко': 'usagiyama_rumi',
    'даки': 'daki_(kimetsu_no_yaiba)',
    'кушина': 'uzumaki_kushina',
    'альфа': 'alpha_(kage_no_jitsuryokusha)',
    'дельта': 'delta_(kage_no_jitsuryokusha)',
    'томоэ': 'tomoe_(tsuki_ga_michibiku_isekai_douchuu)',
    'йосино': 'yoshino_(date_a_live)',
    'куруми': 'tokisaki_kurumi',
    'котори': 'itsuka_kotori',
    'тохка': 'yatogami_tohka',
    'оригами': 'tobiichi_origami',
    'мику': 'izayoi_miku',
    'нацуми': 'kyouno_natsumi',
    'ния': 'honjou_nia',
    'мукуро': 'hoshimiya_mukuro',
    'арин': 'arin_kannazuki',
    'лилит': 'lilith_asami',
    'леви': 'levi_kazama',
    'мира': 'mira_yamana',
    'акио': 'akio_fudou',
    'юи': 'yui_kurata',
    'лизелотта': 'lieselotte_sherlock',
    'селина': 'selina_sherlock',
    'риас гремори': 'rias_gremory',
    'даркнесс': 'darkness_(konosuba)',
    'ноль-два': 'zero_two_(darling_in_the_franxx)',
    'марин китагава': 'kitagawa_marin',
    'люси сердобольская': 'heartfilia_lucy',
    'мираж анна': 'mirajane_strauss',
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
        'page': '${requestedQuery.isEmpty ? 1 : requestedPage}',
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
        hasMore = requestedQuery.isEmpty ? true : data.length >= pageSize;
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
