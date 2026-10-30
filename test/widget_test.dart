import 'package:beside/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el código de invitación se reconoce en enlaces y texto', () {
    expect(inviteCodeFrom('beside://join/BSD-4K7Q'), 'BSD-4K7Q');
    expect(inviteCodeFrom('bsd4k7q'), 'BSD-4K7Q');
    expect(inviteCodeFrom('4k7q'), 'BSD-4K7Q');
    expect(inviteCodeFrom('hola'), isNull);
  });
}
