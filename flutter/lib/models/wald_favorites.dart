// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/wald_peer_names.dart';
import 'package:get/get.dart';

/// Waldlust(DSK-04, 부록 A-53): 카드의 즐겨찾기 별이 읽는 즐겨찾기 id 목록.
///
/// 즐겨찾기 자체는 업스트림 그대로 이 PC 의 로컬 옵션(`fav`)이다. 업스트림 메뉴로 바꿀 때도
/// `bind.mainStoreFav` 뒤에 [set] 을 불러 별 상태를 맞춘다.
class WaldFavorites {
  static final ids = <String>[].obs;
  static bool _loaded = false;

  /// 처음 쓸 때 한 번 읽는다. 읽은 뒤 즐겨찾기 목록을 다시 받아 [fill] 이 빠진 기기를 채우게 한다.
  static void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    bind.mainGetFav().then((favs) {
      ids.value = favs;
      bind.mainLoadFavPeers();
    });
  }

  static void set(List<String> favs) {
    _loaded = true;
    ids.value = favs.toList();
  }

  static Future<void> toggle(String id) async {
    final favs = (await bind.mainGetFav()).toList();
    if (!favs.remove(id)) favs.add(id);
    await bind.mainStoreFav(favs: favs);
    set(favs);
    bind.mainLoadFavPeers();
  }

  /// 즐겨찾기 탭(Rust `main_load_fav_peers`)은 이 PC 에 피어 파일이 있는 기기만 준다 — 접속한 적 없는
  /// 주소록 기기는 빠진다. 빠진 즐겨찾기를 '전체' 주소록(guid `all`)의 기기로, 없으면 어드민 이름만으로 뒤에 붙인다.
  static List<Peer> fill(List<Peer> peers) {
    ensureLoaded();
    final have = peers.map((p) => p.id).toSet();
    final all = gFFI.abModel.addressbooks.values
        .firstWhereOrNull((e) => e.sharedProfile()?.guid == 'all')
        ?.peers;
    for (final id in ids) {
      if (!have.add(id)) continue;
      final p = all?.firstWhereOrNull((e) => e.id == id);
      peers.add(p != null
          ? Peer.copy(p)
          : WaldPeerNames.instance.apply(Peer.fromJson({'id': id})));
    }
    return peers;
  }
}
