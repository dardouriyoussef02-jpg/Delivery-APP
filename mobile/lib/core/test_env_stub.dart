/// Fallback used on platforms without `dart:io` (web): the browser never runs
/// `flutter test`, so there is nothing to detect.
bool isRunningUnderTest() => false;
