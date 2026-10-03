import 'api_client.dart';

/// One heading and its paragraph of the agreement.
class ContractSection {
  const ContractSection({required this.heading, required this.body});

  final String heading;
  final String body;

  factory ContractSection.fromJson(Map<String, dynamic> json) => ContractSection(
        heading: (json['heading'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
      );
}

/// The agreement as the backend serves it - the text is owned server-side so
/// every client renders the same wording and a signed copy can be snapshotted.
class ContractDocument {
  const ContractDocument({
    required this.version,
    required this.title,
    required this.company,
    required this.sections,
    required this.signed,
  });

  final String version;
  final String title;
  final String company;
  final List<ContractSection> sections;
  final bool signed;

  factory ContractDocument.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    return ContractDocument(
      version: (json['version'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Driver Partnership Agreement',
      company: (json['company'] as String?) ?? '',
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((row) => ContractSection.fromJson(row.cast<String, dynamic>()))
              .toList()
          : const [],
      signed: (json['signed'] as bool?) ?? false,
    );
  }
}

/// What signing produced: the recorded signature plus the work dispatched.
class ContractSignResult {
  const ContractSignResult({
    required this.signatureName,
    required this.signedAt,
    required this.assigned,
  });

  final String signatureName;
  final String signedAt;

  /// Stops the company handed over in this call - the queue the driver gets.
  final int assigned;

  factory ContractSignResult.fromJson(Map<String, dynamic> json) {
    final contract = (json['contract'] as Map?)?.cast<String, dynamic>();
    final dispatch = (json['dispatch'] as Map?)?.cast<String, dynamic>();
    return ContractSignResult(
      signatureName: (contract?['signatureName'] as String?) ?? '',
      signedAt: (contract?['signedAt'] as String?) ?? '',
      assigned: (dispatch?['assigned'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Client for the partnership agreement endpoints.
class ContractService {
  ContractService(this._api);

  final ApiClient _api;

  /// `GET /api/v1/contract` - readable before signing, which is the whole
  /// point: the gate must never be a dead end.
  Future<ContractDocument> fetch() async {
    final data = await _api.get('/api/v1/contract');
    if (data is! Map) {
      throw ApiException('The server returned an unexpected contract payload.');
    }
    return ContractDocument.fromJson(data.cast<String, dynamic>());
  }

  /// `POST /api/v1/contract/sign` - records the signature and, on success, the
  /// company dispatches every open delivery to this driver.
  Future<ContractSignResult> sign({
    required String signatureName,
    required bool acknowledged,
  }) async {
    final data = await _api.post(
      '/api/v1/contract/sign',
      body: {'signatureName': signatureName, 'acknowledged': acknowledged},
    );
    if (data is! Map) {
      throw ApiException('The server returned an unexpected response.');
    }
    return ContractSignResult.fromJson(data.cast<String, dynamic>());
  }
}
