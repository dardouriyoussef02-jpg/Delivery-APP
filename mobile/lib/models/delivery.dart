/// Domain models for a delivery stop, mirroring the JSON contract of the
/// existing delivery API.
library;

enum DeliveryStatus {
  pending('pending', 'Scheduled'),
  inTransit('in_transit', 'On the way'),
  failed('failed', 'Attempt failed'),
  delivered('delivered', 'Delivered');

  const DeliveryStatus(this.wire, this.label);

  final String wire;
  final String label;

  static DeliveryStatus fromWire(String? value) =>
      DeliveryStatus.values.firstWhere((status) => status.wire == value, orElse: () => DeliveryStatus.pending);

  bool get isFinished => this == DeliveryStatus.delivered;
}

enum MessageChannel {
  sms('sms', 'SMS'),
  whatsapp('whatsapp', 'WhatsApp'),
  push('push', 'In-app push');

  const MessageChannel(this.wire, this.label);

  final String wire;
  final String label;

  static MessageChannel fromWire(String? value) =>
      MessageChannel.values.firstWhere((channel) => channel.wire == value, orElse: () => MessageChannel.sms);
}

class Customer {
  const Customer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.preferredChannel,
    required this.language,
    this.rating,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String preferredChannel;
  final String language;
  final double? rating;

  String get fullName => '$firstName $lastName';

  String get initials {
    final first = firstName.isEmpty ? '' : firstName[0];
    final last = lastName.isEmpty ? '' : lastName[0];
    return (first + last).toUpperCase();
  }

  MessageChannel get channel => MessageChannel.fromWire(preferredChannel);

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        preferredChannel: json['preferredChannel'] as String? ?? 'sms',
        language: json['language'] as String? ?? 'en',
        rating: (json['rating'] as num?)?.toDouble(),
      );
}

class DeliveryAddress {
  const DeliveryAddress({
    required this.line1,
    required this.city,
    required this.postalCode,
    this.line2 = '',
    this.lat,
    this.lng,
    this.accessHint = '',
  });

  final String line1;
  final String line2;
  final String city;
  final String postalCode;
  final double? lat;
  final double? lng;
  final String accessHint;

  String get singleLine => [line1, if (line2.isNotEmpty) line2, '$postalCode $city'].join(', ');

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) => DeliveryAddress(
        line1: json['line1'] as String? ?? '',
        line2: json['line2'] as String? ?? '',
        city: json['city'] as String? ?? '',
        postalCode: json['postalCode'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        accessHint: json['accessHint'] as String? ?? '',
      );
}

class DeliveryNote {
  const DeliveryNote({
    required this.id,
    required this.author,
    required this.createdAt,
    required this.text,
  });

  final String id;
  final String author;
  final DateTime createdAt;
  final String text;

  bool get fromCustomer => author == 'customer';

  factory DeliveryNote.fromJson(Map<String, dynamic> json) => DeliveryNote(
        id: json['id'] as String? ?? '',
        author: json['author'] as String? ?? 'customer',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        text: json['text'] as String? ?? '',
      );
}

class DeliveryEvent {
  const DeliveryEvent({required this.at, required this.type, required this.label});

  final DateTime at;
  final String type;
  final String label;

  factory DeliveryEvent.fromJson(Map<String, dynamic> json) => DeliveryEvent(
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        type: json['type'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );
}

class Delivery {
  const Delivery({
    required this.id,
    required this.status,
    required this.zone,
    required this.sequence,
    required this.driverId,
    required this.windowStart,
    required this.windowEnd,
    required this.eta,
    required this.distanceKm,
    required this.parcels,
    required this.codAmount,
    required this.currency,
    required this.address,
    required this.customer,
    required this.notes,
    required this.events,
    required this.history,
  });

  final String id;
  final DeliveryStatus status;
  final String zone;
  final int sequence;
  final String driverId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime eta;
  final double distanceKm;
  final int parcels;
  final double codAmount;
  final String currency;
  final DeliveryAddress address;
  final Customer customer;
  final List<DeliveryNote> notes;
  final List<DeliveryEvent> events;
  final List<DeliveryEvent> history;

  bool get needsAttention => status == DeliveryStatus.failed || notes.any((note) => !note.fromCustomer);

  bool get hasAccessInstructions => address.accessHint.trim().isNotEmpty;

  /// The note the assistant should analyse by default: the customer's most
  /// recent one, falling back to the latest internal note.
  DeliveryNote? get primaryNote {
    final fromCustomer = notes.where((note) => note.fromCustomer).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (fromCustomer.isNotEmpty) return fromCustomer.first;
    if (notes.isEmpty) return null;
    final sorted = [...notes]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

  Delivery copyWith({DeliveryStatus? status, List<DeliveryEvent>? events}) => Delivery(
        id: id,
        status: status ?? this.status,
        zone: zone,
        sequence: sequence,
        driverId: driverId,
        windowStart: windowStart,
        windowEnd: windowEnd,
        eta: eta,
        distanceKm: distanceKm,
        parcels: parcels,
        codAmount: codAmount,
        currency: currency,
        address: address,
        customer: customer,
        notes: notes,
        events: events ?? this.events,
        history: history,
      );

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
        id: json['id'] as String? ?? '',
        status: DeliveryStatus.fromWire(json['status'] as String?),
        zone: json['zone'] as String? ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        driverId: json['driverId'] as String? ?? '',
        windowStart: DateTime.tryParse(json['windowStart'] as String? ?? '') ?? DateTime.now(),
        windowEnd: DateTime.tryParse(json['windowEnd'] as String? ?? '') ?? DateTime.now(),
        eta: DateTime.tryParse(json['eta'] as String? ?? '') ?? DateTime.now(),
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        parcels: (json['parcels'] as num?)?.toInt() ?? 0,
        codAmount: (json['codAmount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'EUR',
        address: DeliveryAddress.fromJson((json['address'] as Map?)?.cast<String, dynamic>() ?? const {}),
        customer: Customer.fromJson((json['customer'] as Map?)?.cast<String, dynamic>() ?? const {}),
        notes: ((json['notes'] as List?) ?? const [])
            .map((note) => DeliveryNote.fromJson((note as Map).cast<String, dynamic>()))
            .toList(),
        events: ((json['events'] as List?) ?? const [])
            .map((event) => DeliveryEvent.fromJson((event as Map).cast<String, dynamic>()))
            .toList(),
        history: ((json['history'] as List?) ?? const [])
            .map((event) => DeliveryEvent.fromJson((event as Map).cast<String, dynamic>()))
            .toList(),
      );
}
