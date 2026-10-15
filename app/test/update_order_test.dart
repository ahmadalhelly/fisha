import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/services/update_service.dart';

Release r(String kind, String v, int b) => Release(kind, v, b, '', DateTime(2026), 'u', 1);

void main() {
  final u = UpdateService.instance;

  test('launch 1.0.0 counts as newer than the 2.x builds', () {
    u.releases = [r('app', '2.0.28', 181), r('app', '2.0.29', 182), r('app', '1.0.0', 183), r('hub', '2.15.39', 62), r('hub', '1.0.0', 63)];
    expect(u.latest('app')!.version, '1.0.0');
    expect(u.newer('app', '2.0.28')!.version, '1.0.0');
    expect(u.newer('app', '2.0.29')!.version, '1.0.0');
    expect(u.newer('app', '1.0.0'), isNull);
    expect(u.newer('hub', '2.15.39')!.version, '1.0.0');
    expect(u.newer('hub', '1.0.0'), isNull);
  });

  test('installed version no longer listed', () {
    u.releases = [r('app', '1.0.0', 183), r('hub', '1.0.1', 70)];
    expect(u.newer('app', '2.0.20')!.version, '1.0.0'); // old 2.x removed from the page
    expect(u.newer('hub', '2.15.38')!.version, '1.0.1');
    expect(u.newer('hub', '1.0.0')!.version, '1.0.1'); // falls back to the version name
    expect(u.newer('hub', '1.0.2'), isNull);
  });

  test('normal updates and edge cases', () {
    u.releases = [r('app', '1.0.0', 183), r('app', '1.1.0', 190), r('app', '1.1.0', 188)];
    expect(u.newer('app', '1.0.0')!.version, '1.1.0');
    expect(u.newer('app', '1.1.0'), isNull);
    expect(u.newer('app', 'dev'), isNull);
    expect(u.newer('app', null), isNull);
    expect(u.newer('hub', '1.0.0'), isNull); // no hub releases
    expect(u.buildOf('app', '1.1.0'), 190);
  });
}
