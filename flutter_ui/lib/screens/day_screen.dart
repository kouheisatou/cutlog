// その日の詳細。
// ★ ここだけは web を写さない。web の再生まわりは作りかけなので、Flutter で組み直す。
//   置くのは2つだけ——上に映像、下に縦のドラム。
//   ドラムの真ん中に来たカットが、そのまま流れる。「選ぶ」と「流す」を分けない。
//   進み具合の線は映像のすぐ下に1本だけ。行ごとには付けない。
//   ★行が全部こまかく動くと、どれを見ているのか分からなくなる。
//     区切りの帯を時間で動かすのをやめたのと同じ理由。
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/shell.dart';

class DayScreen extends StatefulWidget {
  const DayScreen({
    super.key,
    required this.date,
    required this.cuts,
    required this.mediaUrl,
    this.onBack,
  });

  final String date;
  final List<Cut> cuts;
  final String Function(String path) mediaUrl;
  final VoidCallback? onBack;

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  /// ドラムの1目盛りの高さ。web の .clip-row（余白 8＋見本 34）と同じ勘定。
  static const double _extent = 50;

  final FixedExtentScrollController _wheel = FixedExtentScrollController();
  VideoPlayerController? _player;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _open(0);
  }

  @override
  void dispose() {
    _player?.dispose();
    _wheel.dispose();
    super.dispose();
  }

  /// 真ん中に来たカットを開いて、そのまま流す。
  Future<void> _open(int i) async {
    if (i < 0 || i >= widget.cuts.length) {
      return;
    }
    final VideoPlayerController? old = _player;
    final Cut cut = widget.cuts[i];

    final VideoPlayerController next =
        VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl(cut.url)));
    // 進み具合の線を動かすため、再生位置の変化をそのまま画面へ流す
    next.addListener(_tick);
    try {
      await next.initialize();
    } catch (e) {
      // ★ 黙って黒いままにしない。読めなかったことが分かるようにする。
      debugPrint('cutlog: 動画を開けません ${widget.mediaUrl(cut.url)} — $e');
      await next.dispose();
      return;
    }
    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() {
      _index = i;
      _player = next;
    });
    await next.play();
    await old?.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
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
    if (_index >= widget.cuts.length) return const SizedBox.expand();
    final String? thumb = widget.cuts[_index].thumbUrl;
    if (thumb == null) return const SizedBox.expand();
    return Center(child: Image.network(widget.mediaUrl(thumb), fit: BoxFit.contain));
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
            onSelectedItemChanged: _open,
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
                  current: i == _index,
                  mediaUrl: widget.mediaUrl,
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
  const _WheelRow({required this.cut, required this.current, required this.mediaUrl});

  final Cut cut;
  final bool current;
  final String Function(String path) mediaUrl;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);
    final String length = '${(cut.durationMs / 1000).toStringAsFixed(1)}秒';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: sp.s4, vertical: sp.s1),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: current ? c.ink : const Color(0x00000000), width: 2),
        ),
      ),
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
                : Image.network(mediaUrl(cut.thumbUrl!), fit: BoxFit.cover),
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
                Text(length, style: t.clipKind),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
