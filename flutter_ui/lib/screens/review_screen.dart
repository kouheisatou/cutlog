// 撮影後の確認。新しく作った画面。
// ★ これまでは撮影の画面の下に細い帯で出していた。撮ったものを確かめる所と、
//   これから撮る所が同じ画面に居ると、どちらの操作か分からなくなる。
//   撮り終えたら画面ごと切り替え、映っているものだけを見せる。
// ★ 地の色は撮影と同じ黒。撮ってから残すまで、明るさが変わらないようにする。
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.url,
    this.destination,
    this.onRetake,
    this.onSave,
    this.onClose,
  });

  /// 撮れたもの。端末に残る前の、その場かぎりの居場所。
  final String url;

  /// どのログへ入るか。撮影の画面から持ち越す。
  final String? destination;

  final VoidCallback? onRetake;
  final ValueChanged<String>? onSave;
  final VoidCallback? onClose;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final TextEditingController _note = TextEditingController();
  VideoPlayerController? _player;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final VideoPlayerController p = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    p.addListener(() {
      if (mounted) setState(() {});
    });
    await p.initialize();
    if (!mounted) {
      await p.dispose();
      return;
    }
    setState(() => _player = p);
    await p.setLooping(true);      // 短いので、確かめるあいだは繰り返し流す
    await p.play();
  }

  @override
  void dispose() {
    _player?.dispose();
    _note.dispose();
    super.dispose();
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
    return total <= 0 ? 0 : (p.value.position.inMilliseconds / total).clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    return ColoredBox(
      color: camBackdrop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 上：閉じると、どこへ入るか ────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(sp.s3, safe.top > sp.s2 ? safe.top : sp.s2, sp.s3, sp.s2),
            child: Row(
              children: <Widget>[
                GestureDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(child: Opacity(opacity: .9, child: Ic('close', color: light))),
                  ),
                ),
                SizedBox(width: sp.s2),
                if ((widget.destination ?? '').isNotEmpty)
                  Flexible(
                    child: Opacity(
                      opacity: .85,
                      child: Text(
                        '記録先 ${widget.destination}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: light,
                          fontFamily: sansFamily,
                          fontSize: 11,
                          height: lineHeight,
                          leadingDistribution: TextLeadingDistribution.even,
                          letterSpacing: tracking(11, .06),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
              ],
            ),
          ),

          // ── 中：撮れたものだけ ────────────────────────
          Expanded(
            child: GestureDetector(
              onTap: _toggle,
              child: ColoredBox(
                color: camBackdrop,
                child: Center(
                  child: _player == null || !_player!.value.isInitialized
                      ? const SizedBox.shrink()
                      : AspectRatio(
                          aspectRatio: _player!.value.aspectRatio,
                          child: VideoPlayer(_player!),
                        ),
                ),
              ),
            ),
          ),

          // 進み具合。撮影の輪と同じ考え方で、線1本だけ。
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sp.s3, vertical: sp.s2),
            child: SizedBox(
              height: 3,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) => Stack(
                  children: <Widget>[
                    const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x52FFFFFF)),
                      child: SizedBox.expand(),
                    ),
                    SizedBox(
                      width: box.maxWidth * _progress,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(color: light),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 下：ひとことを添えて、残すか撮り直すか ────
          Padding(
            padding: EdgeInsets.fromLTRB(sp.s3, 0, sp.s3, (safe.bottom > sp.s3 ? safe.bottom : sp.s3)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0x4DFFFFFF))),
                  ),
                  child: TextField(
                    controller: _note,
                    cursorColor: light,
                    style: const TextStyle(
                      color: light, fontSize: 15, height: lineHeight,
                      leadingDistribution: TextLeadingDistribution.even, fontFamily: sansFamily,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'ひとこと（任意）',
                      hintStyle: TextStyle(
                        color: Color(0x80FFFFFF), fontSize: 15, height: lineHeight,
                        leadingDistribution: TextLeadingDistribution.even, fontFamily: sansFamily,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: sp.s3),
                Row(
                  children: <Widget>[
                    _Action('撮り直し', onTap: widget.onRetake),
                    const Spacer(),
                    _Action('保存', filled: true, onTap: () => widget.onSave?.call(_note.text)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 撮影の画面と同じ手ざわりの押しどころ。強調は反転（白地に黒）で行う。
class _Action extends StatelessWidget {
  const _Action(this.label, {this.filled = false, this.onTap});

  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final TextStyle style = TextStyle(
      color: filled ? const Color(0xFF000000) : const Color(0xD9FFFFFF),
      fontFamily: monoFamily,
      fontFamilyFallback: monoFallback,
      fontSize: 11,
      height: lineHeight,
      leadingDistribution: TextLeadingDistribution.even,
      letterSpacing: tracking(11, track),
      decoration: filled ? TextDecoration.none : TextDecoration.underline,
      decorationColor: const Color(0x8CFFFFFF),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: filled ? EdgeInsets.symmetric(horizontal: sp.s3, vertical: 10) : EdgeInsets.zero,
        alignment: Alignment.center,
        color: filled ? light : null,
        child: Text(upper(label), style: style),
      ),
    );
  }
}
