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
    sequence: 1,
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
    sequence: 2,
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
    sequence: 3,
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
    sequence: 4,
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
  {
    id: 'DLV-1046',
    status: 'pending',
    zone: 'Delfshaven',
    sequence: 5,
    driverId: null,
    windowStart: minutes(272),
    windowEnd: minutes(332),
    eta: minutes(284),
    distanceKm: 3.6,
    parcels: 1,
    codAmount: 0,
    currency: 'EUR',
    item: {
      name: 'Cordless drill',
      category: 'Power tools',
      sku: 'SKU-DRL-5507',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/1/18/Cordless_drill_Metabo_BS_14%2C4_Li.JPG/960px-Cordless_drill_Metabo_BS_14%2C4_Li.JPG',
    },
    address: {
      line1: '92 Schiedamseweg',
      line2: 'Ground floor, left bell',
      city: 'Rotterdam',
      postalCode: '3013 BH',
      lat: 51.9152,
      lng: 4.4449,
      accessHint: 'Ring bell 2 - the names on the intercom are unreadable',
    },
    customer: {
      id: 'CUS-5108',
      firstName: 'Ayse',
      lastName: 'Yilmaz',
      phone: '+31 6 2211 3344',
      preferredChannel: 'whatsapp',
      language: 'nl',
      rating: 4.7,
    },
    notes: [
      {
        id: 'NOTE-6',
        author: 'customer',
        createdAt: minutes(-12),
        text: 'I am at work until 17:30 - my neighbour at 92B can sign for it if I am not back in time.',
      },
    ],
    events: [{ at: minutes(-25), type: 'assigned', label: 'Assigned to driver' }],
    history: [],
  },
  {
    id: 'DLV-1047',
    status: 'in_transit',
    zone: 'Charlois',
    sequence: 6,
    driverId: null,
    windowStart: minutes(344),
    windowEnd: minutes(404),
    eta: minutes(356),
    distanceKm: 7.8,
    parcels: 1,
    codAmount: 145.0,
    currency: 'EUR',
    item: {
      name: 'Acoustic guitar',
      category: 'Musical instruments',
      sku: 'SKU-GTR-7723',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5d/00_Walden_Acoustic_Guitar_D310e_01.jpg/960px-00_Walden_Acoustic_Guitar_D310e_01.jpg',
    },
    address: {
      line1: '45 Wolphaertsbocht',
      line2: 'Houseboat De Reiger, mooring 12',
      city: 'Rotterdam',
      postalCode: '3082 AJ',
      lat: 51.8946,
      lng: 4.4791,
      accessHint: 'The gangway is steep - call out and I will come up to meet you',
    },
    customer: {
      id: 'CUS-3372',
      firstName: 'Ruben',
      lastName: 'dos Santos',
      phone: '+31 6 8877 1122',
      preferredChannel: 'push',
      language: 'en',
      rating: 4.5,
    },
    notes: [
      {
        id: 'NOTE-7',
        author: 'customer',
        createdAt: minutes(-35),
        text: 'Cash on delivery is EUR 145 - please bring change, I only have a EUR 200 note.',
      },
    ],
    events: [
      { at: minutes(-70), type: 'assigned', label: 'Assigned to driver' },
      { at: minutes(-40), type: 'picked_up', label: 'Guitar picked up at the hub' },
    ],
    history: [{ at: minutes(-5000), outcome: 'delivered', label: 'Left at the back door' }],
  },
  {
    id: 'DLV-1048',
    status: 'pending',
    zone: 'Blijdorp',
    sequence: 7,
    driverId: null,
    windowStart: minutes(416),
    windowEnd: minutes(476),
    eta: minutes(431),
    distanceKm: 5.4,
    parcels: 1,
    codAmount: 89.5,
    currency: 'EUR',
    item: {
      name: 'Microwave oven',
      category: 'Kitchen appliances',
      sku: 'SKU-MCW-8814',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/b/bb/Microwave_Oven.jpg/960px-Microwave_Oven.jpg',
    },
    address: {
      line1: '128 Kruiskade',
      line2: 'Flat 3C, third floor',
      city: 'Rotterdam',
      postalCode: '3012 EH',
      lat: 51.9212,
      lng: 4.4703,
      accessHint: 'Lift is out of order - third floor on foot',
    },
    customer: {
      id: 'CUS-8456',
      firstName: 'Fatima',
      lastName: 'El Amrani',
      phone: '+31 6 3344 5566',
      preferredChannel: 'sms',
      language: 'nl',
      rating: 4.9,
    },
    notes: [
      {
        id: 'NOTE-8',
        author: 'dispatcher',
        createdAt: minutes(-18),
        text: 'Fragile goods: the customer asked for it to be handed over in person, no doorstep drop.',
      },
    ],
    events: [{ at: minutes(-28), type: 'assigned', label: 'Assigned to driver' }],
    history: [],
  },
  {
    id: 'DLV-1049',
    status: 'failed',
    zone: 'Katendrecht',
    sequence: 8,
    driverId: null,
    windowStart: minutes(-40),
    windowEnd: minutes(20),
    eta: minutes(-22),
    distanceKm: 2.9,
    parcels: 2,
    codAmount: 0,
    currency: 'EUR',
    item: {
      name: 'Bicycle helmet',
      category: 'Cycling gear',
      sku: 'SKU-HLM-2044',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/Bicycle_white_helmet_from_bikemate.jpg/960px-Bicycle_white_helmet_from_bikemate.jpg',
    },
    address: {
      line1: '7 Brede Hilledijk',
      line2: '',
      city: 'Rotterdam',
      postalCode: '3072 BK',
      lat: 51.8921,
      lng: 4.4889,
      accessHint: 'Buzzer is broken - call on arrival',
    },
    customer: {
      id: 'CUS-2197',
      firstName: 'Kees',
      lastName: 'Vermeulen',
      phone: '+31 6 5566 7788',
      preferredChannel: 'sms',
      language: 'nl',
      rating: 4.2,
    },
    notes: [
      {
        id: 'NOTE-9',
        author: 'customer',
        createdAt: minutes(-40),
        text: 'Yesterday nobody was home - sorry. I finish work at 15:00 today, please retry after that.',
      },
    ],
    events: [
      { at: minutes(-165), type: 'assigned', label: 'Assigned to driver' },
      { at: minutes(-105), type: 'picked_up', label: 'Parcels picked up at hub' },
      { at: minutes(-45), type: 'failed', label: 'Recipient unavailable' },
    ],
    history: [{ at: minutes(-2000), outcome: 'failed', label: 'Recipient unavailable' }],
  },
  {
    id: 'DLV-1050',
    status: 'pending',
    zone: 'Hillegersberg',
    sequence: 9,
    driverId: null,
    windowStart: minutes(492),
    windowEnd: minutes(552),
    eta: minutes(508),
    distanceKm: 8.3,
    parcels: 4,
    codAmount: 33.75,
    currency: 'EUR',
    item: {
      name: 'Board game',
      category: 'Toys and games',
      sku: 'SKU-BRD-6691',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/3/32/Just_One_party_game_box%2C_rules%2C_cards%2C_and_pieces_01.jpg/960px-Just_One_party_game_box%2C_rules%2C_cards%2C_and_pieces_01.jpg',
    },
    address: {
      line1: '12 Bergse Dorpsstraat',
      line2: 'Side entrance, blue door',
      city: 'Rotterdam',
      postalCode: '3054 LC',
      lat: 51.9475,
      lng: 4.4739,
      accessHint: 'Double door - please leave the boxes inside the porch',
    },
    customer: {
      id: 'CUS-6631',
      firstName: 'Olga',
      lastName: 'Nowak',
      phone: '+31 6 6677 8899',
      preferredChannel: 'whatsapp',
      language: 'en',
      rating: 4.8,
    },
    notes: [
      {
        id: 'NOTE-10',
        author: 'customer',
        createdAt: minutes(-10),
        text: 'It is a surprise - do not ring before 14:00, the children must not see the boxes.',
      },
    ],
    events: [{ at: minutes(-20), type: 'assigned', label: 'Assigned to driver' }],
    history: [{ at: minutes(-7000), outcome: 'delivered', label: 'Handed over in person' }],
  },
  {
    id: 'DLV-1051',
    status: 'failed',
    zone: 'Overschie',
    sequence: 10,
    driverId: null,
    windowStart: minutes(-75),
    windowEnd: minutes(-15),
    eta: minutes(-58),
    distanceKm: 12.6,
    parcels: 1,
    codAmount: 210.0,
    currency: 'EUR',
    item: {
      name: 'Baby stroller',
      category: 'Baby and nursery',
      sku: 'SKU-PRM-3388',
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/1/12/Stroller_or_pram_pic3.JPG/960px-Stroller_or_pram_pic3.JPG',
    },
    address: {
      line1: '510 Delftseweg',
      line2: 'Business park, unit 14',
      city: 'Rotterdam',
      postalCode: '3043 GH',
      lat: 51.9294,
      lng: 4.4187,
      accessHint: 'Gate closes at 17:00 sharp - press the buzzer for unit 14',
    },
    customer: {
      id: 'CUS-9904',
      firstName: 'Jia-Ling',
      lastName: 'Chen',
      phone: '+31 6 9900 1122',
      preferredChannel: 'push',
      language: 'en',
      rating: 4.6,
    },
    notes: [
      {
        id: 'NOTE-11',
        author: 'dispatcher',
        createdAt: minutes(-55),
        text: 'Recipient refused the package because the box was crushed - photographs sent to dispatch.',
      },
    ],
    events: [
      { at: minutes(-205), type: 'assigned', label: 'Assigned to driver' },
      { at: minutes(-140), type: 'picked_up', label: 'Stroller picked up at hub' },
      { at: minutes(-60), type: 'failed', label: 'Damaged goods' },
    ],
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
