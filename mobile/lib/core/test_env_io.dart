import 'dart:io';

/// `flutter test` spawns the Dart VM with `FLUTTER_TEST` set in the
/// environment. Used to keep deliberately infinite animations (the ON DUTY
/// ping) from stalling `WidgetTester.pumpAndSettle`.
bool isRunningUnderTest() => Platform.environment.containsKey('FLUTTER_TEST');
