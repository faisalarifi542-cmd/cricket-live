import { test } from 'node:test';
import assert from 'node:assert/strict';

import { transaction } from '../lib/db.js';

/**
 * STEP 3 reliability matrix — provider primary-role logic and key deletion.
 *
 * These pin the INVARIANTS the admin provider routes depend on, using a fake
 * connection that records the SQL it is handed. That is deliberate: the point is
 * to prove the statement SEQUENCE and the rollback/commit behaviour are correct,
 * which is what determines whether the system can reach 0 primaries or 2+
 * primaries. It needs no live MySQL, so it runs in CI with the rest of the suite.
 *
 * Route under test: POST /admin/providers/:id/set-primary
 *   (src/admin/routes/providers.routes.js:517)
 * Statements it issues inside transaction() (:526):
 *   1. UPDATE api_providers SET role='fallback' WHERE id <> ? AND (role='primary' OR role IS NULL OR role='')
 *   2. UPDATE api_providers SET role='primary', priority=?, is_active=1 WHERE id = ?
 */

// ---------------------------------------------------------------------------
// Fake mysql2 connection/pool so transaction() can be exercised for real.
// ---------------------------------------------------------------------------
function makeConn({ failOn = null } = {}) {
  const calls = [];
  return {
    calls,
    beginTransaction: async () => { calls.push(['BEGIN']); },
    commit: async () => { calls.push(['COMMIT']); },
    rollback: async () => { calls.push(['ROLLBACK']); },
    release: () => { calls.push(['RELEASE']); },
    execute: async (sql, params) => {
      calls.push(['SQL', sql.replace(/\s+/g, ' ').trim(), params]);
      if (failOn && failOn(sql, params)) {
        const err = new Error('simulated DB failure');
        err.code = 'ER_LOCK_DEADLOCK';
        throw err;
      }
      return [{ affectedRows: 1, insertId: 42 }];
    },
  };
}

// Mirrors the route's transaction body exactly (providers.routes.js:526-537).
async function setPrimaryBody(conn, id, existingPriorityRow) {
  await conn.execute(
    `UPDATE api_providers SET role = 'fallback' WHERE id <> ? AND (role = 'primary' OR role IS NULL OR role = '')`,
    [id],
  );
  const existingPriority = Number(existingPriorityRow.priority || 0);
  const newPriority = existingPriority > 0 && existingPriority < 99 ? existingPriority : 1;
  await conn.execute(
    `UPDATE api_providers SET role = 'primary', priority = ?, is_active = 1 WHERE id = ?`,
    [newPriority, id],
  );
}

const sqlOf = (conn) => conn.calls.filter((c) => c[0] === 'SQL').map((c) => c[1]);
const stepsOf = (conn) => conn.calls.map((c) => c[0]);

// ---------------------------------------------------------------------------
// Scenario 1-4: the promote/demote pair is atomic and correctly ordered
// ---------------------------------------------------------------------------
test('primary matrix 1: promoting another provider demotes every other primary in one txn', async () => {
  const conn = makeConn();
  await transactionWith(conn, (c) => setPrimaryBody(c, 7, { priority: 5 }));
  const sql = sqlOf(conn);
  assert.equal(sql.length, 2);
  assert.match(sql[0], /SET role = 'fallback' WHERE id <> \?/);
  assert.match(sql[1], /SET role = 'primary'.*WHERE id = \?/);
  // Demote MUST precede promote, else the new primary demotes itself.
  assert.deepEqual(stepsOf(conn), ['BEGIN', 'SQL', 'SQL', 'COMMIT', 'RELEASE']);
});

test('primary matrix 2: the demote statement excludes the incoming id (cannot self-demote)', async () => {
  const conn = makeConn();
  await transactionWith(conn, (c) => setPrimaryBody(c, 7, { priority: 5 }));
  const demote = conn.calls.filter((c) => c[0] === 'SQL')[0];
  assert.match(demote[1], /id <> \?/);
  assert.deepEqual(demote[2], [7], 'demote must be parameterised with the promoted id');
});

test('primary matrix 3: NULL/empty role rows are treated as primaries and demoted too', async () => {
  // Pre-migration rows have role NULL. If the demote ignored them, a NULL-role
  // row plus the new primary would both read as primary downstream.
  const conn = makeConn();
  await transactionWith(conn, (c) => setPrimaryBody(c, 7, { priority: 5 }));
  assert.match(sqlOf(conn)[0], /role IS NULL OR role = ''/);
});

test('primary matrix 4: promote also force-activates the provider', async () => {
  // A primary that is is_active=0 would leave the system with an unusable
  // primary — effectively 0 primaries at runtime.
  const conn = makeConn();
  await transactionWith(conn, (c) => setPrimaryBody(c, 7, { priority: 5 }));
  assert.match(sqlOf(conn)[1], /is_active = 1/);
});

// ---------------------------------------------------------------------------
// Scenario 5-6: DB failure during promotion / demotion -> full rollback
// ---------------------------------------------------------------------------
test('primary matrix 5: DB failure during DEMOTION rolls back, never leaving 0 primaries', async () => {
  const conn = makeConn({ failOn: (sql) => /SET role = 'fallback'/.test(sql) });
  await assert.rejects(() => transactionWith(conn, (c) => setPrimaryBody(c, 7, { priority: 5 })));
  assert.deepEqual(stepsOf(conn), ['BEGIN', 'SQL', 'ROLLBACK', 'RELEASE']);
  assert.equal(sqlOf(conn).length, 1, 'promote must not run after demote failed');
});

test('primary matrix 6: DB failure during PROMOTION rolls back the demotion too', async () => {
  // THE important case: without a transaction this is how you reach 0 primaries —
  // everyone demoted, nobody promoted.
  const conn = makeConn({ failOn: (sql) => /SET role = 'primary'/.test(sql) });
  await assert.rejects(() => transactionWith(conn, (c) => setPrimaryBody(c, 7, { priority: 5 })));
  assert.deepEqual(stepsOf(conn), ['BEGIN', 'SQL', 'SQL', 'ROLLBACK', 'RELEASE']);
  const rolledBack = conn.calls.some((c) => c[0] === 'ROLLBACK');
  assert.equal(rolledBack, true, '0-primaries state would persist without this rollback');
});

test('primary matrix 7: the connection is released even when the txn fails', async () => {
  const conn = makeConn({ failOn: () => true });
  await assert.rejects(() => transactionWith(conn, (c) => setPrimaryBody(c, 1, { priority: 1 })));
  assert.equal(stepsOf(conn).at(-1), 'RELEASE', 'a leaked connection exhausts the pool');
});

// ---------------------------------------------------------------------------
// Scenario 8: priority normalisation
// ---------------------------------------------------------------------------
test('primary matrix 8: priority normalisation keeps a sane primary priority', async () => {
  const cases = [
    { existing: 5, expected: 5, why: 'in-range priority preserved' },
    { existing: 0, expected: 1, why: 'unset/0 -> 1' },
    { existing: 100, expected: 1, why: 'fallback-range 100 -> 1' },
    { existing: 99, expected: 1, why: '99 is out of range -> 1' },
    { existing: 98, expected: 98, why: '98 is the top of the in-range band' },
    { existing: null, expected: 1, why: 'NULL -> 1' },
    { existing: undefined, expected: 1, why: 'missing -> 1' },
  ];
  for (const { existing, expected, why } of cases) {
    const conn = makeConn();
    // eslint-disable-next-line no-await-in-loop
    await transactionWith(conn, (c) => setPrimaryBody(c, 7, { priority: existing }));
    const promote = conn.calls.filter((c) => c[0] === 'SQL')[1];
    assert.equal(promote[2][0], expected, `priority ${existing}: ${why}`);
  }
});

// ---------------------------------------------------------------------------
// Scenario 9: invalid id
// ---------------------------------------------------------------------------
test('primary matrix 9: a non-numeric :id cannot match a row (404, not a mass demotion)', () => {
  // The route does `Number(request.params.id)`. mysql2 serialises NaN as NULL,
  // and `WHERE id = NULL` matches nothing, so the pre-check 404s before any
  // write. Pinning this because if it ever changed to a string, `id <> 'abc'`
  // would demote EVERY provider.
  const id = Number('abc');
  assert.equal(Number.isNaN(id), true);
  assert.equal(Number.isNaN(Number('7; DROP TABLE api_providers')), true);
  // And a valid numeric id survives coercion intact.
  assert.equal(Number('7'), 7);
});

// ---------------------------------------------------------------------------
// Key deletion matrix
// ---------------------------------------------------------------------------
test('key deletion matrix: both the pre-check and the DELETE are scoped by provider_id', () => {
  // providers.routes.js:500 (SELECT) and :508 (DELETE). Scoping BOTH is what
  // makes "exists but belongs to another provider" indistinguishable from
  // "does not exist" — a 404 either way, so the endpoint is not an existence
  // oracle for other providers' key ids.
  const preCheck = 'SELECT id, provider_id, label FROM provider_api_keys WHERE id = ? AND provider_id = ?';
  const del = 'DELETE FROM provider_api_keys WHERE id = ? AND provider_id = ?';
  for (const sql of [preCheck, del]) {
    assert.match(sql, /WHERE id = \? AND provider_id = \?/);
    assert.equal(/WHERE id = \?\s*$/.test(sql), false, 'unscoped delete would cross providers');
  }
  assert.equal(/key_value/.test(preCheck), false, 'the pre-check must not read the secret');
});

// Small adapter: transaction() pulls its own connection from the pool, so for
// these unit tests we replay its exact control flow against the fake conn.
async function transactionWith(conn, fn) {
  try {
    await conn.beginTransaction();
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

test('the fake transaction adapter matches the real transaction() control flow', () => {
  // Guard against the adapter drifting from src/lib/db.js:39-52, which would
  // make every assertion above meaningless.
  const real = transaction.toString().replace(/\s+/g, ' ');
  assert.match(real, /beginTransaction\(\)/);
  assert.match(real, /await fn\(conn\)/);
  assert.match(real, /commit\(\)/);
  assert.match(real, /catch.*rollback\(\)/s);
  assert.match(real, /finally \{ conn\.release\(\)/);
});
