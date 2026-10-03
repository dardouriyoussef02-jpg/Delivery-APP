/**
 * Demo stand-in for the customer's existing delivery backend.
 *
 * The mobile app and the agent both talk to this store when
 * `EXISTING_API_BASE_URL` is not configured, so the whole product can be
 * demonstrated end-to-end without touching production data.
 *
 * Every record mirrors the payload shape described by the client's API docs:
 * delivery code, customer, address, time window, status, customer notes and an
 * event timeline.
 */

const now = Date.now();
const minutes = (n) => new Date(now + n * 60_000).toISOString();

/** @typedef {'pending'|'in_transit'|'failed'|'delivered'} DeliveryStatus */

export const deliveries = [
  {
    id: 'DLV-1042',
    status: 'in_transit',
    zone: 'Riverside',
    sequence: 3,
    driverId: null,
    windowStart: minutes(18),
    windowEnd: minutes(78),
    eta: minutes(32),
    distanceKm: 4.2,
    parcels: 2,
    codAmount: 24.9,
    currency: 'EUR',
    item: {
      name: 'Espresso machine',
      category: 'Small appliances',
      sku: 'SKU-ESP-2201',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9b/Espresso_machine_1.jpg/960px-Espresso_machine_1.jpg',
    },
    address: {
      line1: '18 Kanalstraat',
      line2: 'Flat 4B, 2nd floor',
      city: 'Rotterdam',
      postalCode: '3011 AB',
      lat: 51.9161,
      lng: 4.4795,
      accessHint: 'Buzzer 4B is broken - call on arrival',
    },
    customer: {
      id: 'CUS-8821',
      firstName: 'Sanne',
      lastName: 'de Vries',
      phone: '+31 6 1234 5678',
      preferredChannel: 'sms',
      language: 'nl',
      rating: 4.8,
    },
    notes: [
      {
        id: 'NOTE-1',
        author: 'customer',
        createdAt: minutes(-46),
        text: 'Gate code 4482, please leave the parcels with my neighbour at no. 20 if I do not open. I am in a meeting until 16:00.',
      },
      {
        id: 'NOTE-2',
        author: 'dispatcher',
        createdAt: minutes(-30),
        text: 'Customer asked for a delivery update when the driver is 10 minutes away.',
      },
    ],
    events: [
      { at: minutes(-95), type: 'assigned', label: 'Assigned to driver' },
      { at: minutes(-60), type: 'picked_up', label: 'Parcels picked up at hub' },
      { at: minutes(-12), type: 'in_transit', label: 'On the way to Kanalstraat' },
    ],
    history: [
      { at: minutes(-4320), outcome: 'delivered', label: 'Delivered on first attempt' },
      { at: minutes(-10_080), outcome: 'delivered', label: 'Left with neighbour' },
    ],
  },
  {
    id: 'DLV-1043',
    status: 'in_transit',
    zone: 'Nieuwe Westen',
    sequence: 4,
    driverId: null,
    windowStart: minutes(60),
    windowEnd: minutes(120),
    eta: minutes(58),
    distanceKm: 6.7,
    parcels: 1,
    codAmount: 0,
    currency: 'EUR',
    item: {
      name: '46-inch LED TV',
      category: 'Electronics',
      sku: 'SKU-TV-4608',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3b/TV_set_%2846_inch%29_in_self-customized_box_for_sending_via_parcel_service_N.1.jpg/960px-TV_set_%2846_inch%29_in_self-customized_box_for_sending_via_parcel_service_N.1.jpg',
    },
    address: {
      line1: '204 Delfshavenseweg',
      line2: '',
      city: 'Rotterdam',
      postalCode: '3024 AK',
      lat: 51.9054,
      lng: 4.4372,
      accessHint: '',
    },
    customer: {
      id: 'CUS-9013',
      firstName: 'Marco',
      lastName: 'Bianchi',
      phone: '+31 6 9876 5432',
      preferredChannel: 'whatsapp',
      language: 'en',
      rating: 4.6,
    },
    notes: [
      {
        id: 'NOTE-3',
        author: 'customer',
        createdAt: minutes(-22),
        text: 'Parcel arrived damaged, the box is crushed and the seal is open. I want to refuse it.',
      },
    ],
    events: [
      { at: minutes(-88), type: 'assigned', label: 'Assigned to driver' },
      { at: minutes(-52), type: 'picked_up', label: 'Parcel picked up at hub' },
    ],
    history: [{ at: minutes(-7200), outcome: 'delivered', label: 'Delivered on first attempt' }],
  },
  {
    id: 'DLV-1044',
    status: 'pending',
    zone: 'Kralingen',
    sequence: 5,
    driverId: null,
    windowStart: minutes(130),
    windowEnd: minutes(190),
    eta: minutes(141),
    distanceKm: 9.1,
    parcels: 3,
    codAmount: 61.4,
    currency: 'EUR',
    item: {
      name: 'Ergonomic office chair',
      category: 'Office furniture',
      sku: 'SKU-OFC-3310',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/7/7b/ErgoFlip_Active_Ergonomic_Chair_with_2_surfaces.jpg',
    },
    address: {
      line1: '7 Laan van Coolsingen',
      line2: 'Office 1.12',
      city: 'Rotterdam',
      postalCode: '3015 AE',
      lat: 51.9155,
      lng: 4.4966,
      accessHint: 'Reception closes at 17:00 sharp',
    },
    customer: {
      id: 'CUS-7742',
      firstName: 'Priya',
      lastName: 'Nair',
      phone: '+31 6 5555 0199',
      preferredChannel: 'sms',
      language: 'en',
      rating: 4.9,
    },
    notes: [
      {
        id: 'NOTE-4',
        author: 'customer',
        createdAt: minutes(-15),
        text: 'Can we move this to tomorrow morning? Nobody will be in the office today, sorry for the short notice.',
      },
    ],
    events: [{ at: minutes(-40), type: 'assigned', label: 'Assigned to driver' }],
    history: [{ at: minutes(-1440), outcome: 'failed', label: 'Recipient unavailable' }],
  },
  {
    id: 'DLV-1045',
    status: 'pending',
    zone: 'Feijenoord',
    sequence: 6,
    driverId: null,
    windowStart: minutes(200),
    windowEnd: minutes(260),
    eta: minutes(205),
    distanceKm: 11.4,
    parcels: 1,
    codAmount: 12.0,
    currency: 'EUR',
    item: {
      name: 'Running shoes',
      category: 'Sportswear',
      sku: 'SKU-SHO-1145',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b8/Mizuno_Wave_Ibuki_2.jpg/960px-Mizuno_Wave_Ibuki_2.jpg',
    },
    address: {
      line1: '51 Oranjeboomstraat',
      line2: '',
      city: 'Rotterdam',
      postalCode: '3072 XK',
      lat: 51.8926,
      lng: 4.4875,
      accessHint: '',
    },
    customer: {
      id: 'CUS-6650',
      firstName: 'Joris',
      lastName: 'Bakker',
      phone: '+31 6 4444 7788',
      preferredChannel: 'sms',
      language: 'nl',
      rating: 4.4,
    },
    notes: [
      {
        id: 'NOTE-5',
        author: 'customer',
        createdAt: minutes(-8),
        text: 'Ring the bell twice, I am hard of hearing. Please do not leave it in the porch.',
      },
    ],
    events: [{ at: minutes(-33), type: 'assigned', label: 'Assigned to driver' }],
    history: [],
  },
];

const clone = (value) => JSON.parse(JSON.stringify(value));

export const deliveryStore = {
  /** @returns {Promise<object|null>} */
  async list({ driverId } = {}) {
    const rows = deliveries
      .filter((d) => !driverId || d.driverId === driverId)
      .sort((a, b) => a.sequence - b.sequence)
      .map(clone);
    return rows;
  },

  /** @returns {Promise<object|null>} */
  async get(id) {
    const found = deliveries.find((d) => d.id === id);
    return found ? clone(found) : null;
  },

  /** @returns {Promise<object|null>} */
  async updateStatus(id, status, { label } = {}) {
    const found = deliveries.find((d) => d.id === id);
    if (!found) return null;
    found.status = status;
    found.events.push({
      at: new Date().toISOString(),
      type: status,
      label: label ?? `Status changed to ${status}`,
    });
    return clone(found);
  },

  /** Outbox for messages the driver actually pressed "send" on. */
  outbox: [],

  async sendMessage(message) {
    const record = {
      messageId: `MSG-${String(this.outbox.length + 1).padStart(4, '0')}`,
      sentAt: new Date().toISOString(),
      ...message,
    };
    this.outbox.push(record);
    return record;
  },
};

export default deliveryStore;
