import 'package:beside/main.dart';
import 'package:beside/services/updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el código de invitación se reconoce en enlaces y texto', () {
    expect(inviteCodeFrom('beside://join/BSD-4K7Q'), 'BSD-4K7Q');
    expect(inviteCodeFrom('bsd4k7q'), 'BSD-4K7Q');
    expect(inviteCodeFrom('4k7q'), 'BSD-4K7Q');
    expect(inviteCodeFrom('hola'), isNull);
  });

  test('detecta cuándo hay una versión más nueva', () {
    expect(Updates.isNewer('v1.1.0', 'v1.0.3'), isTrue);
    expect(Updates.isNewer('v1.0.10', 'v1.0.9'), isTrue);
    expect(Updates.isNewer('v1.0.3', 'v1.0.3'), isFalse);
    expect(Updates.isNewer('v1.0.2', 'v1.0.3'), isFalse);
  });
}
