import type { Pool, PoolClient } from 'pg';
import type { OptionType } from '../domain/types.js';
import { runFenced, type LedgerFence } from '../persistence/ledger.js';

/** A paper position as the venue holds it. Prices are per unit; money is rupees rounded to paise. */
export interface PaperPositionRecord {
  readonly positionId: string;
  readonly clientId: string;
  readonly underlying: string;
  readonly securityId: string;
  readonly exchangeSegment: string;
  readonly tickSize: number;
  readonly quantity: number;
  readonly averagePrice: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  readonly openedAt: number;
  /** Contract terms for expiry settlement. Absent on positions recorded before they were stored. */
  readonly expiry?: string | undefined;
  readonly strike?: number | undefined;
  readonly optionType?: OptionType | undefined;
}

export interface PaperOrderRecord {
  readonly correlationId: string;
  readonly positionId: string;
  readonly kind: 'ENTRY' | 'EXIT' | 'PROTECTIVE_EXIT' | 'EXPIRY';
  readonly side: 'BUY' | 'SELL';
  readonly quantity: number;
  readonly price: number;
  readonly reason: string | undefined;
  readonly at: number;
}

export type OpenEntryResult = 'OPENED' | 'INSUFFICIENT_CASH' | 'DUPLICATE';
export type CloseResult = 'CLOSED' | 'NOT_OPEN';

/**
 * The venue's durable state. Every method is one fenced transaction, so a run that lost the trading lease cannot
 * move paper cash or positions. The venue reads its state back from here on start.
 */
export interface PaperStore {
  /** Creates the wallet with its starting capital. Refuses when a wallet exists with a different starting capital. */
  ensureWallet(clientId: string, initialInr: number): Promise<void>;
  balance(clientId: string): Promise<number>;
  openPositions(clientId: string): Promise<PaperPositionRecord[]>;
  /** Debits the wallet by `debitInr` and records the position and its entry order, unless cash or the id is not available. */
  openPosition(input: { position: PaperPositionRecord; order: PaperOrderRecord; debitInr: number }): Promise<OpenEntryResult>;
  /** Credits the wallet by `creditInr`, records the realised P&L and the exit order, and closes the position. */
  closePosition(input: {
    clientId: string;
    positionId: string;
    order: PaperOrderRecord;
    creditInr: number;
    exitPrice: number;
    exitReason: string;
    realizedPnlInr: number;
    at: number;
  }): Promise<CloseResult>;
}

/** Rupees to paise, the precision the wallet stores. */
export function toPaise(value: number): number {
  return Math.round(value * 100) / 100;
}

export class PostgresPaperStore implements PaperStore {
  constructor(
    private readonly pool: Pool,
    private readonly fence: LedgerFence,
  ) {}

  async ensureWallet(clientId: string, initialInr: number): Promise<void> {
    const amount = toPaise(initialInr);
    await runFenced(this.pool, this.fence, async (client) => {
      await client.query(
        'INSERT INTO paper_wallets (client_id, initial_inr, balance_inr) VALUES ($1, $2, $2) ON CONFLICT (client_id) DO NOTHING',
        [clientId, amount],
      );
      const { rows } = await client.query<{ initial: number }>(
        'SELECT initial_inr::float8 AS initial FROM paper_wallets WHERE client_id = $1',
        [clientId],
      );
      if (rows[0]?.initial !== amount) {
        throw new Error(
          `the paper wallet for client ${clientId} started with ${rows[0]?.initial ?? 'an unknown amount'} INR; CAPITAL_INR is ${amount}. ` +
            'Reset the wallet or use another client id; the starting capital of an existing wallet is not changed silently',
        );
      }
    });
  }

  async balance(clientId: string): Promise<number> {
    const { rows } = await this.pool.query<{ balance: number }>(
      'SELECT balance_inr::float8 AS balance FROM paper_wallets WHERE client_id = $1',
      [clientId],
    );
    if (rows[0] === undefined) {
      throw new Error(`no paper wallet for client ${clientId}`);
    }
    return rows[0].balance;
  }

  async openPositions(clientId: string): Promise<PaperPositionRecord[]> {
    const { rows } = await this.pool.query<PositionRow>(
      `SELECT position_id, client_id, underlying, security_id, exchange_segment,
              tick_size::float8 AS tick_size, quantity, average_price::float8 AS average_price,
              stop_loss_price::float8 AS stop_loss_price, target_price::float8 AS target_price, opened_at,
              to_char(expiry, 'YYYY-MM-DD') AS expiry, strike::float8 AS strike, option_type
       FROM paper_positions WHERE client_id = $1 AND status = 'OPEN' ORDER BY opened_at, position_id`,
      [clientId],
    );
    return rows.map((row) => ({
      positionId: row.position_id,
      clientId: row.client_id,
      underlying: row.underlying,
      securityId: row.security_id,
      exchangeSegment: row.exchange_segment,
      tickSize: row.tick_size,
      quantity: row.quantity,
      averagePrice: row.average_price,
      stopLossPrice: row.stop_loss_price,
      targetPrice: row.target_price,
      openedAt: row.opened_at.getTime(),
      expiry: row.expiry ?? undefined,
      strike: row.strike ?? undefined,
      optionType: row.option_type ?? undefined,
    }));
  }

  async openPosition(input: { position: PaperPositionRecord; order: PaperOrderRecord; debitInr: number }): Promise<OpenEntryResult> {
    const { position, order } = input;
    const debit = toPaise(input.debitInr);
    return runFenced(this.pool, this.fence, async (client) => {
      const wallet = await client.query<{ balance: number }>(
        'SELECT balance_inr::float8 AS balance FROM paper_wallets WHERE client_id = $1 FOR UPDATE',
        [position.clientId],
      );
      const balance = wallet.rows[0]?.balance;
      if (balance === undefined) {
        throw new Error(`no paper wallet for client ${position.clientId}`);
      }
      if (balance < debit) {
        return 'INSUFFICIENT_CASH';
      }
      const inserted = await client.query(
        `INSERT INTO paper_positions (position_id, client_id, underlying, security_id, exchange_segment, tick_size, quantity,
                                      average_price, stop_loss_price, target_price, status, opened_at, expiry, strike, option_type)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'OPEN', $11, $12, $13, $14)
         ON CONFLICT (position_id) DO NOTHING`,
        [
          position.positionId,
          position.clientId,
          position.underlying,
          position.securityId,
          position.exchangeSegment,
          position.tickSize,
          position.quantity,
          position.averagePrice,
          position.stopLossPrice,
          position.targetPrice,
          new Date(position.openedAt).toISOString(),
          position.expiry ?? null,
          position.strike ?? null,
          position.optionType ?? null,
        ],
      );
      if ((inserted.rowCount ?? 0) === 0) {
        return 'DUPLICATE';
      }
      await insertOrder(client, position.clientId, order);
      await debitWallet(client, position.clientId, -debit, order.correlationId, order.at);
      return 'OPENED';
    });
  }

  async closePosition(input: {
    clientId: string;
    positionId: string;
    order: PaperOrderRecord;
    creditInr: number;
    exitPrice: number;
    exitReason: string;
    realizedPnlInr: number;
    at: number;
  }): Promise<CloseResult> {
    const credit = toPaise(input.creditInr);
    return runFenced(this.pool, this.fence, async (client) => {
      const closed = await client.query(
        `UPDATE paper_positions
            SET status = 'CLOSED', closed_at = $3, exit_price = $4, exit_reason = $5, realized_pnl_inr = $6
          WHERE position_id = $1 AND client_id = $2 AND status = 'OPEN'`,
        [
          input.positionId,
          input.clientId,
          new Date(input.at).toISOString(),
          input.exitPrice,
          input.exitReason,
          toPaise(input.realizedPnlInr),
        ],
      );
      if ((closed.rowCount ?? 0) === 0) {
        return 'NOT_OPEN';
      }
      await insertOrder(client, input.clientId, input.order);
      await debitWallet(client, input.clientId, credit, input.order.correlationId, input.order.at);
      return 'CLOSED';
    });
  }
}

interface PositionRow {
  position_id: string;
  client_id: string;
  underlying: string;
  security_id: string;
  exchange_segment: string;
  tick_size: number;
  quantity: number;
  average_price: number;
  stop_loss_price: number;
  target_price: number;
  opened_at: Date;
  expiry: string | null;
  strike: number | null;
  option_type: OptionType | null;
}

async function insertOrder(
  client: PoolClient,
  clientId: string,
  order: PaperOrderRecord,
): Promise<void> {
  await client.query(
    `INSERT INTO paper_orders (correlation_id, position_id, client_id, kind, side, quantity, price, reason, at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      order.correlationId,
      order.positionId,
      clientId,
      order.kind,
      order.side,
      order.quantity,
      order.price,
      order.reason ?? null,
      new Date(order.at).toISOString(),
    ],
  );
}

/** Applies a signed cash movement and records the balance it leaves. The CHECK on the wallet refuses a negative balance. */
async function debitWallet(
  client: PoolClient,
  clientId: string,
  delta: number,
  correlationId: string,
  at: number,
): Promise<void> {
  const updated = await client.query<{ balance: number }>(
    'UPDATE paper_wallets SET balance_inr = balance_inr + $2, updated_at = now() WHERE client_id = $1 RETURNING balance_inr::float8 AS balance',
    [clientId, delta],
  );
  const balanceAfter = updated.rows[0]?.balance;
  if (balanceAfter === undefined) {
    throw new Error(`no paper wallet for client ${clientId}`);
  }
  await client.query(
    'INSERT INTO paper_wallet_entries (client_id, correlation_id, delta_inr, balance_after_inr, at) VALUES ($1, $2, $3, $4, $5)',
    [clientId, correlationId, delta, balanceAfter, new Date(at).toISOString()],
  );
}
