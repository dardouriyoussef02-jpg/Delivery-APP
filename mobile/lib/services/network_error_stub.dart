/// Fallback used on platforms without `dart:io` (web), where `package:http`
/// surfaces connection problems as `ClientException` instead.
bool isNetworkError(Object error) => false;
