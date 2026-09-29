import 'dotenv/config';

function num(value, fallback) {
  const parsed = Number.parseInt(value ?? '', 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function bool(value, fallback) {
  if (value === undefined || value === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

const config = {
  env: process.env.NODE_ENV ?? 'development',
  host: process.env.HOST ?? '0.0.0.0',
  port: num(process.env.PORT, 8787),

  llm: {
    provider: (process.env.LLM_PROVIDER ?? 'mock').toLowerCase(),
    anthropicKey: process.env.ANTHROPIC_API_KEY ?? '',
    anthropicModel: process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-4-5',
    anthropicMaxTokens: num(process.env.ANTHROPIC_MAX_TOKENS, 1500),
    anthropicUrl: process.env.ANTHROPIC_URL ?? 'https://api.anthropic.com/v1/messages',
    anthropicTimeoutMs: num(process.env.ANTHROPIC_TIMEOUT_MS, 45_000),
    /** What to do when the real LLM cannot answer: "mock" (offline rules) or "off". */
    fallback: (process.env.LLM_FALLBACK ?? 'mock').toLowerCase(),
  },

  existingApi: {
    baseUrl: (process.env.EXISTING_API_BASE_URL ?? '').replace(/\/+$/, ''),
    apiKey: process.env.EXISTING_API_KEY ?? '',
    get enabled() {
      return this.baseUrl.length > 0;
    },
  },

  auth: {
    /** Legacy service-to-service secret; a user session is the primary credential. */
    driverToken: process.env.DRIVER_API_TOKEN ?? '',
    sessionTtlHours: num(process.env.SESSION_TTL_HOURS, 12),
    get sessionTtlMs() {
      return this.sessionTtlHours * 3_600_000;
    },
    /**
     * Self-registration of driver accounts (`ALLOW_SIGNUP`, default on).
     * Set to false on a locked-down fleet server where drivers are created
     * by dispatch instead.
     */
    get allowSignup() {
      return bool(process.env.ALLOW_SIGNUP, true);
    },
    /** First-run users, configured through the environment (never hard-coded). */
    seed: {
      get driverId() {
        return process.env.SEED_DRIVER_ID ?? 'DRV-77';
      },
      get driverEmail() {
        return (process.env.SEED_DRIVER_EMAIL ?? 'driver@fleet.local').trim().toLowerCase();
      },
      get driverPassword() {
        return process.env.SEED_DRIVER_PASSWORD ?? '';
      },
      get adminId() {
        return process.env.SEED_ADMIN_ID ?? 'ADM-01';
      },
      get adminEmail() {
        return (process.env.SEED_ADMIN_EMAIL ?? 'admin@fleet.local').trim().toLowerCase();
      },
      get adminPassword() {
        return process.env.SEED_ADMIN_PASSWORD ?? '';
      },
    },
  },

  db: {
    /** SQLite file used for persistent deliveries, messages, users and sessions. */
    path: process.env.DATABASE_PATH ?? 'data/delivery.db',
  },

  guardrails: {
    maxAgentTurns: num(process.env.MAX_AGENT_TURNS, 6),
    maxMessageChars: num(process.env.MAX_MESSAGE_CHARS, 320),
    minMessageChars: num(process.env.MIN_MESSAGE_CHARS, 40),
    /** Banned because a driver message is service comms, never marketing. */
    bannedWords: ['discount', 'promo', 'free', 'guarantee', 'winner', 'subscribe'],
    /** Abusive/insulting language is never sent to a customer. */
    abusiveWords: ['idiot', 'stupid', 'moron', 'idiotic', 'shut up', 'incompetent', 'bastard', 'asshole', 'useless'],
  },

  telemetry: bool(process.env.LOG_TOOL_CALLS, true),
};

export default config;
