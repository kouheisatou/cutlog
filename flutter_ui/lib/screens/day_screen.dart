// その日の詳細。
// ★ ここだけは web を写さない。web の再生まわりは作りかけなので、Flutter で組み直す。
//   置くのは2つだけ——上に映像、下に縦のドラム。
//   ドラムの真ん中に来たカットが、そのまま流れる。「選ぶ」と「流す」を分けない。
//   進み具合の線は映像のすぐ下に1本だけ。行ごとには付けない。
//   ★行が全部こまかく動くと、どれを見ているのか分からなくなる。
//     区切りの帯を時間で動かすのをやめたのと同じ理由。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../data/media.dart';
import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/shell.dart';

class DayScreen extends StatefulWidget {
  const DayScreen({
    super.key,
    required this.date,
    required this.cuts,
    required this.media,
    required this.cutSeconds,
    this.onBack,
    this.onToggleHidden,
    this.onComments,
    this.onDetail,
    this.onShare,
    this.onRender,
  });

  final String date;
  final List<Cut> cuts;
  final Media media;

  /// 1カットの長さ（秒）。ログごとに違う。
  final int cutSeconds;

  final VoidCallback? onBack;

  /// 出す・出さないを切り替える。だめならその訳が返る。
  final Future<String?> Function(Cut cut, bool hidden)? onToggleHidden;

  final ValueChanged<Cut>? onComments;
  final ValueChanged<Cut>? onDetail;
  final VoidCallback? onShare;
  final VoidCallback? onRender;

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  /// ドラムの1目盛りの高さ。
  /// ★ 中身は 余白8＋（名前 23.8＋2＋長さ 17）＋余白8 = 58.8。
  ///   50 のままだと下がはみ出す（実機で「9px 溢れています」と出た）。
  static const double _extent = 59;

  final FixedExtentScrollController _wheel = FixedExtentScrollController();
  VideoPlayerController? _player;
  int _index = 0;          // _playable の中での位置
  String? _playingId;      // いま流しているカット
  bool _muted = false;

  /// 流すのは、出すことにしているカットだけ。
  /// ★ 非表示は時間軸に入れない。行には残るが、つないだ再生からは外れる。
  List<Cut> get _playable => widget.cuts.where((Cut c) => !c.hidden).toList();

  /// 通しの長さ（ミリ秒）。1カットの長さは、ログの決めと実長の短い方。
  int get _totalMs => _playable.fold(0, (int n, Cut c) => n + _durOf(c));

  int _durOf(Cut c) {
    final int unit = widget.cutSeconds * 1000;
    if (c.durationMs <= 0) return unit;
    return c.durationMs < unit ? c.durationMs : unit;
  }

  /// いま通しで何ミリ秒めか
  int get _atMs {
    int before = 0;
    for (int i = 0; i < _index && i < _playable.length; i++) {
      before += _durOf(_playable[i]);
    }
    final VideoPlayerController? p = _player;
    final int inside = p == null || !p.value.isInitialized ? 0 : p.value.position.inMilliseconds;
    final int cap = _index < _playable.length ? _durOf(_playable[_index]) : 0;
    return before + (inside > cap ? cap : inside);
  }

  static String _clock(int ms) {
    final int s = (ms / 1000).floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _open(0);
  }

  @override
  void didUpdateWidget(DayScreen old) {
    super.didUpdateWidget(old);
    // ★ 中身が入れ替わったら、真ん中の行を選び直す。
    //   非表示を戻した直後は、どれを流しているかが宙に浮いたままになる。
    if (old.cuts.length != widget.cuts.length ||
        !identical(old.cuts, widget.cuts)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final int at = _wheel.hasClients ? _wheel.selectedItem : 0;
        if (at >= 0 && at < widget.cuts.length && !widget.cuts[at].hidden) {
          if (_playingId != widget.cuts[at].id) _pick(at);
        }
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _wheel.dispose();
    super.dispose();
  }

  /// ドラムで真ん中に来た行を受ける。
  /// ★ 非表示の行は流さない。web と同じく、目のアイコンで戻せることだけ知らせる。
  void _pick(int at) {
    if (at < 0 || at >= widget.cuts.length) return;
    final Cut cut = widget.cuts[at];
    if (cut.hidden) {
      setState(() => _playingId = null);
      _player?.pause();
      toast(context, '非表示のクリップです。目のしるしで表示に戻せます');
      return;
    }
    final int i = _playable.indexWhere((Cut c) => c.id == cut.id);
    if (i >= 0) _open(i);
  }

  /// 真ん中に来たカットを開いて、そのまま流す。
  Future<void> _open(int i) async {
    if (i < 0 || i >= _playable.length) {
      return;
    }
    final VideoPlayerController? old = _player;
    final Cut cut = _playable[i];

    final VideoPlayerController next =
        VideoPlayerController.networkUrl(
      Uri.parse(widget.media.url(cut.url)),
      // ★ cookie を添えないと 401 になり、黒いまま何も起きない
      httpHeaders: widget.media.headers,
    );
    // 進み具合の線を動かすため、再生位置の変化をそのまま画面へ流す
    next.addListener(_tick);
    try {
      // ★ 返ってこないことがある（web の video_player）。待ちきりにしない。
      await next.initialize().timeout(const Duration(seconds: 6));
    } catch (e) {
      // ★ 黙って黒いままにしない。読めなかったことが分かるようにする。
      debugPrint('cutlog: 動画を開けません ${widget.media.url(cut.url)} — $e');
      await next.dispose();
      return;
    }
    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() {
      _index = i;
      _playingId = cut.id;
      _player = next;
    });
    await next.setVolume(_muted ? 0 : 1);
    await next.play();
    await old?.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final VideoPlayerController? p = _player;
    // ★ 1カットぶん流し終えたら、次のカットへ自分で進む。
    //   端まで行ったら止める（頭へ戻して延々回さない）。
    if (p != null && p.value.isInitialized && _index < _playable.length) {
      final int cap = _durOf(_playable[_index]);
      if (p.value.position.inMilliseconds >= cap - 30 && p.value.isPlaying) {
        _next();
        return;
      }
    }
    setState(() {});
  }

  /// いま流しているカットの、全部の並びでの位置
  int get _rowIndex =>
      _playingId == null ? 0 : widget.cuts.indexWhere((Cut c) => c.id == _playingId);

  void _next() {
    // 次に流せる行まで送る（非表示は飛ばす）
    for (int at = _rowIndex + 1; at < widget.cuts.length; at++) {
      if (widget.cuts[at].hidden) continue;
      _wheel.animateToItem(at,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      return;
    }
    _player?.pause();
    setState(() {});
  }

  /// 前へ。1.5秒より進んでいれば、まず今のカットの頭へ戻す。
  void _prev() {
    final VideoPlayerController? p = _player;
    final bool intoIt = p != null && p.value.isInitialized && p.value.position.inMilliseconds > 1500;
    if (intoIt) {
      p.seekTo(Duration.zero);
      setState(() {});
      return;
    }
    for (int at = _rowIndex - 1; at >= 0; at--) {
      if (widget.cuts[at].hidden) continue;
      _wheel.animateToItem(at,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      return;
    }
    p?.seekTo(Duration.zero);
    setState(() {});
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _player?.setVolume(_muted ? 0 : 1);
  }

  void _toggle() {
    final VideoPlayerController? p = _player;
    if (p == null || !p.value.isInitialized) return;
    p.value.isPlaying ? p.pause() : p.play();
  }

  double get _progress {
    final VideoPlayerController? p = _player;
    if (p == null || !p.value.isInitialized) return 0;
    final int total = p.value.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (p.value.position.inMilliseconds / total).clamp(0, 1);
  }

  /// 映像の代わりに敷く1枚。いま選んでいるカットのサムネ。
  Widget _poster() {
    if (_index >= _playable.length) return const SizedBox.expand();
    final String? thumb = _playable[_index].thumbUrl;
    if (thumb == null) return const SizedBox.expand();
    return Center(child: CachedNetworkImage(imageUrl: widget.media.url(thumb), httpHeaders: widget.media.headers, fit: BoxFit.contain));
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TopBar(children: <Widget>[
          IconBtn('back', onTap: widget.onBack),
          Text(widget.date.replaceAll('-', '.'), style: Typo(c).crumbCurrent),
          const Spacer(),
        ]),

        // ── 映像。空いている所は全部こちらへ渡す。 ────
        // ★ ドラムを伸ばすと、カットが少ない日に大きな空白ができる。
        //   伸びるのは映像の側、ドラムは決まった高さで下に座らせる。
        Expanded(
          child: GestureDetector(
            onTap: _toggle,
            child: ColoredBox(
              color: camBackdrop,
              // ★ 映像が出るまで黒いままにしない。まずサムネを敷く。
              //   読み込みの間も「どのカットを見ているか」が途切れない。
              child: _player != null && _player!.value.isInitialized
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: _player!.value.aspectRatio,
                        child: VideoPlayer(_player!),
                      ),
                    )
                  : _poster(),
            ),
          ),
        ),

        // ── 進み具合。線1本だけ。 ─────────────────────
        _ProgressLine(value: _progress),

        // ── 操作。再生・前後・音・全画面と、通しの時計。 ──
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spaceOf(context).s4),
          child: Row(
            children: <Widget>[
              IconBtn(
                _player?.value.isPlaying ?? false ? 'pause' : 'play',
                size: 38,
                label: _player?.value.isPlaying ?? false ? '一時停止' : '再生',
                onTap: _toggle,
              ),
              IconBtn('prev', size: 38, label: '前のクリップ', onTap: _prev),
              IconBtn('next', size: 38, label: '次のクリップ', onTap: _next),
              SizedBox(width: spaceOf(context).s1),
              Text('${_clock(_atMs)} / ${_clock(_totalMs)}',
                  style: Typo(c).mini.copyWith(decoration: TextDecoration.none)),
              const Spacer(),
              IconBtn(_muted ? 'mute' : 'sound', size: 38,
                  label: _muted ? '音を出す' : '音を消す', onTap: _toggleMute),
              IconBtn('share', size: 38, label: '共有', onTap: widget.onShare),
              IconBtn('download', size: 38, label: '動画を保存', onTap: widget.onRender),
            ],
          ),
        ),

        // ── ドラム ────────────────────────────────────
        SizedBox(
          height: _extent * 5,
          child: ListWheelScrollView.useDelegate(
            controller: _wheel,
            itemExtent: _extent,
            // 丸みを強くして、筒が回っているように見せる
            diameterRatio: 1.6,
            perspective: 0.005,
            physics: const FixedExtentScrollPhysics(),
            // 濃さは自分で配る（既定は真ん中以外がひと律に薄くなるだけ）
            overAndUnderCenterOpacity: 1,
            // ★ 虫めがね（useMagnifier）は使わない。
            //   真ん中を別の層で描くので、こちらで配った濃さと噛み合わず、
            //   ちょうど真ん中の1行が消えてしまう。
            onSelectedItemChanged: _pick,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.cuts.length,
              builder: (BuildContext context, int i) => AnimatedBuilder(
                animation: _wheel,
                builder: (BuildContext context, Widget? child) {
                  // ★ 真ん中からの隔たりで、だんだん薄くする。
                  //   ひと律に薄くすると板を並べたように見え、筒に見えない。
                  final double at = _wheel.hasClients && _wheel.position.hasPixels
                      ? _wheel.offset / _extent
                      : _index.toDouble();
                  final double away = (i - at).abs();
                  final double fade = (1 - away * 0.42).clamp(0.14, 1.0);
                  return Opacity(opacity: fade, child: child);
                },
                child: _WheelRow(
                  cut: widget.cuts[i],
                  current: widget.cuts[i].id == _playingId,
                  media: widget.media,
                  length: _durOf(widget.cuts[i]),
                  onHide: widget.onToggleHidden == null
                      ? null
                      : () => widget.onToggleHidden!(
                            widget.cuts[i], !widget.cuts[i].hidden),
                  onComments: widget.onComments,
                  onDetail: widget.onDetail,
                ),
              ),
            ),
          ),
        ),
        // 下の帯のぶんだけ空ける。ドラムは帯のすぐ上に座らせる。
        // ★ ここを詰めないと、ドラムと帯のあいだに宙ぶらりんの空白ができる。
        SizedBox(height: 57 + MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

/// 進み具合。web の .segbar と同じ細さ（3px）で、1本だけ引く。
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(sp.s4, sp.s2, sp.s4, sp.s1),
      child: SizedBox(
        height: 3,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) => Stack(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(color: c.hair, borderRadius: BorderRadius.circular(2)),
                child: const SizedBox.expand(),
              ),
              SizedBox(
                width: box.maxWidth * value,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(2)),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ドラムの1行。いまのカットの行を、そのまま目盛りにしたもの。
/// 真ん中の1行だけ、左に2pxの印を立てる（web の .clip-row.now と同じしるし）。
class _WheelRow extends StatelessWidget {
  const _WheelRow({
    required this.cut,
    required this.current,
    required this.media,
    required this.length,
    this.onHide,
    this.onComments,
    this.onDetail,
  });

  final Cut cut;
  final bool current;
  final Media media;

  /// この行が流れる長さ（ミリ秒）
  final int length;

  final VoidCallback? onHide;
  final ValueChanged<Cut>? onComments;
  final ValueChanged<Cut>? onDetail;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);
    final String len = '${(length / 1000).toStringAsFixed(1)}秒';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: sp.s4, vertical: sp.s1),
      decoration: BoxDecoration(
        // CSS: .clip-row.now — いま流れている行にだけ、左に2pxのしるし
        border: Border(
          left: BorderSide(color: current ? c.ink : const Color(0x00000000), width: 2),
        ),
      ),
      // CSS: .clip-row.off — 非表示のぶんは薄く。消えてはいない。
      foregroundDecoration: cut.hidden
          ? BoxDecoration(color: c.paper.withValues(alpha: .55))
          : null,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(cut.hhmm,
                style: t.timeCode.copyWith(color: current ? c.ink : c.mute)),
          ),
          SizedBox(width: sp.s2),
          Container(
            width: 56,
            height: 34,
            decoration: BoxDecoration(color: c.paper2),
            clipBehavior: Clip.hardEdge,
            child: cut.thumbUrl == null
                ? null
                : CachedNetworkImage(imageUrl: media.url(cut.thumbUrl!), httpHeaders: media.headers, fit: BoxFit.cover),
          ),
          SizedBox(width: sp.s2),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  (cut.note ?? '').isNotEmpty ? cut.note! : (cut.author ?? ''),
                  style: t.clipName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(len, style: t.clipKind),
              ],
            ),
          ),

          // 行ごとの操作。真ん中の行にだけ出す（並びが騒がしくならないように）。
          if (current || cut.hidden) ...<Widget>[
            IconBtn(cut.hidden ? 'eye-off' : 'eye', size: 38,
                label: cut.hidden ? '表示に戻す' : '非表示にする', onTap: onHide),
            IconBtn('comment', size: 38, label: 'コメント',
                onTap: onComments == null ? null : () => onComments!(cut)),
            IconBtn('settings', size: 38, label: '詳細',
                onTap: onDetail == null ? null : () => onDetail!(cut)),
          ],
        ],
      ),
    );
  }
}
