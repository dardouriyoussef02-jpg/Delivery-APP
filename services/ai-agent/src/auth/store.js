/**
 * Storage interface for users (drivers) and login sessions.
 *
 * Phase 1 ships a process-local implementation so authentication works before
 * the database layer lands; `src/data/sqlite_store.js` provides the durable
 * implementation with the exact same surface, so routes never care where the
 * rows live.
 *
 * @typedef {object} AuthStore
 * @property {(email: string) => Promise<object|null>} findUserByEmail
 * @property {(id: string) => Promise<object|null>} findUserById
 * @property {() => Promise<number>} countUsers
 * @property {(user: {id:string,email:string,name:string,role:string,passwordHash:string}) => Promise<object>} createUser
 * @property {(rows: Array<{id:string,email:string,name:string,role:string,passwordHash:string}>) => Promise<void>} createUsers
 * @property {(session: {tokenHash:string,userId:string,expiresAt:string}) => Promise<void>} createSession
 * @property {(tokenHash: string) => Promise<object|null>} findSession
 * @property {(tokenHash: string) => Promise<void>} deleteSession
 * @property {(userId: string) => Promise<void>} deleteSessionsForUser
 * @property {() => Promise<number>} purgeExpiredSessions
 */

const normalise = (email) => String(email ?? '').trim().toLowerCase();

/** Process-local auth store: users + sessions kept in Maps. */
export function createMemoryAuthStore() {
  const users = new Map(); // id -> user
  const sessions = new Map(); // tokenHash -> session

  return {
    async findUserByEmail(email) {
      const needle = normalise(email);
      for (const user of users.values()) {
        if (user.email === needle) return { ...user };
      }
      return null;
    },

    async findUserById(id) {
      const user = users.get(id);
      return user ? { ...user } : null;
    },

    async countUsers() {
      return users.size;
    },

    async createUser(user) {
      const record = { ...user, email: normalise(user.email), active: 1 };
      users.set(record.id, record);
      return { ...record };
    },

    async createUsers(rows) {
      for (const row of rows) await this.createUser(row);
    },

    async createSession(session) {
      sessions.set(session.tokenHash, { ...session, createdAt: new Date().toISOString() });
    },

    async findSession(tokenHash) {
      const session = sessions.get(tokenHash);
      if (!session) return null;
      if (Date.parse(session.expiresAt) <= Date.now()) {
        sessions.delete(tokenHash);
        return null;
      }
      return { ...session };
    },

    async deleteSession(tokenHash) {
      sessions.delete(tokenHash);
    },

    async deleteSessionsForUser(userId) {
      for (const [hash, session] of sessions) {
        if (session.userId === userId) sessions.delete(hash);
      }
    },

    async purgeExpiredSessions() {
      const now = Date.now();
      let removed = 0;
      for (const [hash, session] of sessions) {
        if (Date.parse(session.expiresAt) <= now) {
          sessions.delete(hash);
          removed += 1;
        }
      }
      return removed;
    },
  };
}

export default createMemoryAuthStore;
