// マップ。web の #mapScreen をそのまま写す。
// ★ 地図そのものは外の部品に任せ、ここでは器とピンの見た目だけを決める。
//   web は Leaflet、こちらは flutter_map。瓦（タイル）の出どころは同じ。
// ★ 近いピンは束ねる。束ねたものを押したときは、寄るのではなく中身の一覧へ進む。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/media.dart';
import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.cuts,
    required this.media,
    required this.tileUrl,
    this.onOpen,
  });

  final List<Cut> cuts;
  final Media media;
  final String tileUrl;
  final ValueChanged<List<Cut>>? onOpen;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// 束ねるときの隔たり（画面の上での px）。web の maxClusterRadius と同じ。
  static const double _clusterRadius = 60;

  double _zoom = 9;

  List<Cut> get _placed =>
      widget.cuts.where((Cut c) => c.lat != null && c.lon != null).toList();

  /// はじめの一度だけ、撮った場所が全部入るところへ合わせる。
  /// ★ 出したあとに動かしてはいけない。動かすと、取りに行きかけていた瓦が
  ///   全部打ち切られ、そのまま取り直されない（48枚とも打ち切られていた）。
  ///   最初の見え方として渡せば、その位置ぶんだけを取りに行く。
  CameraFit? get _cameraFit {
    final List<Cut> at = _placed;
    if (at.isEmpty) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(at.map((Cut c) => LatLng(c.lat!, c.lon!)).toList()),
      padding: const EdgeInsets.all(40),     // web の fitBounds と同じ余白
      maxZoom: 16,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final List<Cut> at = _placed;

    return ColoredBox(
      color: c.paper2,
      child: Stack(
        // ★ 緩い箱のままだと、地図が自分の大きさを決められず瓦を取りに行かない。
        //   広がる箱にして、はっきり大きさを渡す。
        fit: StackFit.expand,
        children: <Widget>[
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(35.68, 139.77),
              initialZoom: 9,
              initialCameraFit: _cameraFit,
              maxZoom: 19,
              onPositionChanged: (MapCamera cam, bool _) => _zoom = cam.zoom,
            ),
            children: <Widget>[
              TileLayer(userAgentPackageName: 'dev.cutlog', urlTemplate: widget.tileUrl),
              MarkerLayer(markers: _pins(at)),
            ],
          ),
          if (at.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('位置情報のあるカットがまだありません。',
                    textAlign: TextAlign.center, style: Typo(c).empty),
              ),
            ),
          // CSS: .map-count — 何件を出しているか、左下に小さく
          Positioned(
            left: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${at.length}件',
                style: TextStyle(
                  color: c.inkSoft,
                  fontFamily: monoFamily,
                  fontFamilyFallback: monoFallback,
                  fontSize: 10,
                  height: lineHeight,
                  leadingDistribution: TextLeadingDistribution.even,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 近いものを束ねてピンにする。
  /// ★ 画面の上での隔たりで束ねる（緯度経度の差ではない）。寄れば解ける、離せば束ねる。
  List<Marker> _pins(List<Cut> at) {
    final List<List<Cut>> groups = <List<Cut>>[];
    final double scale = math.pow(2, _zoom).toDouble() * 256 / 360;   // 経度1度あたりの px

    for (final Cut cut in at) {
      List<Cut>? near;
      for (final List<Cut> g in groups) {
        final Cut head = g.first;
        final double dx = (cut.lon! - head.lon!) * scale;
        final double dy = (cut.lat! - head.lat!) * scale * 1.3;       // 緯度側のおおよその伸び
        if (math.sqrt(dx * dx + dy * dy) < _clusterRadius) {
          near = g;
          break;
        }
      }
      (near ?? (groups..add(<Cut>[])).last).add(cut);
    }

    return groups.map((List<Cut> g) {
      // 束ねたときの見本は、いちばん新しいカット
      final Cut head = g.reduce((Cut a, Cut b) => a.takenAt.compareTo(b.takenAt) > 0 ? a : b);
      return Marker(
        point: LatLng(head.lat!, head.lon!),
        width: 46,
        height: 46,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => widget.onOpen?.call(g),
          child: _Pin(cut: head, count: g.length, media: widget.media),
        ),
      );
    }).toList();
  }
}

/// CSS: .map-pin — 44px の丸。白い縁を回し、束ねたものは数を右上に出す。
class _Pin extends StatelessWidget {
  const _Pin({required this.cut, required this.count, required this.media});

  final Cut cut;
  final int count;
  final Media media;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.paper,
            border: Border.all(color: c.paper, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                offset: const Offset(0, 2),
                blurRadius: blurFromCss(6),
                color: const Color(0x47000000),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: cut.thumbUrl == null
              ? null
              : Tn(media.url(cut.thumbUrl!), headers: media.headers),
        ),
        if (count > 1)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.sel,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.paper, width: 2),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: c.selInk,
                  fontFamily: monoFamily,
                  fontFamilyFallback: monoFallback,
                  fontSize: 10,
                  height: 20 / 10,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
