import 'dart:io';

/// Socket-level failures (no network, host unreachable) on the VM-based
/// platforms (Android, iOS, desktop).
bool isNetworkError(Object error) =>
    error is SocketException || error is HandshakeException || error is TlsException;
