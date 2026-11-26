/**
 * Thin client for the paper_exchange REST API (github.com/shubhamtaywade82/paper_exchange, `/api`).
 *
 * Failure classification matters more than the happy path. A 4xx (other than 408 and 429) means the server refused
 * the request before acting on it, so the caller may report it as rejected. A network error, a timeout, or a 5xx
 * means the server may or may not have acted, so the caller must treat it as unconfirmed. The API key is sent in a
 * header and is never part of an error message.
 */

export type PaperExchangeFailure = 'REJECTED' | 'UNCONFIRMED';

export class PaperExchangeError extends Error {
  constructor(
    message: string,
    readonly failure: PaperExchangeFailure,
    readonly status: number | undefined,
  ) {
    super(message);
    this.name = 'PaperExchangeError';
  }
}

export interface PaperExchangeClientOptions {
  readonly baseUrl: string;
  readonly apiKey: string;
  readonly accountId: string;
  readonly timeoutMs: number;
  readonly fetch?: typeof fetch;
}

/** A paper_exchange order as the API returns it. Only the fields the agent reads are typed. */
export interface PaperOrder {
  readonly id: number;
  readonly clientOrderId: string | undefined;
  readonly status: 'pending' | 'open' | 'partially_filled' | 'filled' | 'cancelled' | 'rejected' | 'expired' | 'unknown';
  readonly filledQuantity: number;
}

export interface PaperLedgerEntry {
  readonly eventType: string;
  readonly payload: Record<string, unknown>;
}

export interface PaperPosition {
  readonly id: number;
  readonly symbol: string;
  readonly netQuantity: number;
}

const KNOWN_STATUSES: ReadonlySet<string> = new Set(['pending', 'open', 'partially_filled', 'filled', 'cancelled', 'rejected', 'expired']);

export class PaperExchangeClient {
  private readonly fetchImpl: typeof fetch;

  constructor(private readonly options: PaperExchangeClientOptions) {
    this.fetchImpl = options.fetch ?? fetch;
  }

  /**
   * The account's currency and available balance. The server keeps each account in one currency, and Indian
   * instruments settle in INR, so the caller checks the currency before trading.
   */
  async account(): Promise<{ currency: string; availableBalance: number }> {
    const record = asRecord(await this.request('GET', '/api/account'));
    const value = Number(record['available_balance']);
    if (!Number.isFinite(value)) {
      throw new PaperExchangeError('paper_exchange account has no usable available_balance', 'UNCONFIRMED', undefined);
    }
    return { currency: String(record['currency'] ?? ''), availableBalance: value };
  }

  /** Available balance for the account. The entry sizing and the funds check read this. */
  async availableBalance(): Promise<number> {
    return (await this.account()).availableBalance;
  }

  async positions(): Promise<PaperPosition[]> {
    const body = await this.request('GET', '/api/positions');
    return asArray(body).map((row) => {
      const record = asRecord(row);
      return {
        id: Number(record['id']),
        symbol: String(record['symbol'] ?? ''),
        netQuantity: Number(record['net_quantity'] ?? 0),
      };
    });
  }

  /** Places an order. A `client_order_id` that already exists returns that order, so a retry cannot double-order. */
  async placeOrder(body: Record<string, unknown>): Promise<PaperOrder> {
    return parseOrder(await this.request('POST', '/api/orders', body));
  }

  async order(id: number): Promise<PaperOrder> {
    return parseOrder(await this.request('GET', `/api/orders/${id}`));
  }

  async cancelOrder(id: number): Promise<PaperOrder> {
    return parseOrder(await this.request('DELETE', `/api/orders/${id}`));
  }

  /** One page of the account's ledger, newest first. `cursor` is opaque; it is undefined on the first page. */
  async ledgerPage(cursor: string | undefined): Promise<{ entries: PaperLedgerEntry[]; nextCursor: string | undefined }> {
    const query = new URLSearchParams({ limit: '100' });
    if (cursor !== undefined) {
      query.set('cursor', cursor);
    }
    const body = asRecord(await this.request('GET', `/api/ledger?${query.toString()}`));
    return {
      entries: asArray(body['data']).map((row) => {
        const record = asRecord(row);
        return { eventType: String(record['event_type'] ?? ''), payload: asRecord(record['payload']) };
      }),
      nextCursor: typeof body['next_cursor'] === 'string' ? body['next_cursor'] : undefined,
    };
  }

  /** Removes the API key from any text that could reach a log, even if the server echoed it back. */
  private redact(text: string): string {
    return text.split(this.options.apiKey).join('***');
  }

  private async request(method: 'GET' | 'POST' | 'DELETE', path: string, body?: Record<string, unknown>): Promise<unknown> {
    const url = `${this.options.baseUrl}${path}`;
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        method,
        headers: {
          Accept: 'application/json',
          'X-API-Key': this.options.apiKey,
          'X-Account-Id': this.options.accountId,
          ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: AbortSignal.timeout(this.options.timeoutMs),
      });
    } catch (error) {
      // Network failure or timeout: the request may have reached the server.
      throw new PaperExchangeError(this.redact(`paper_exchange ${method} ${path} did not answer: ${networkMessage(error)}`), 'UNCONFIRMED', undefined);
    }
    const text = await response.text();
    if (!response.ok) {
      const failure: PaperExchangeFailure = isDefinitiveRefusal(response.status) ? 'REJECTED' : 'UNCONFIRMED';
      throw new PaperExchangeError(
        this.redact(`paper_exchange ${method} ${path} answered ${response.status}: ${errorText(text)}`),
        failure,
        response.status,
      );
    }
    if (text.trim() === '') {
      return {};
    }
    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw new PaperExchangeError(`paper_exchange ${method} ${path} returned a body that is not JSON`, 'UNCONFIRMED', response.status);
    }
  }
}

/**
 * A 4xx that proves the server did not act. Three are not refusals of an order. 408 and 429 can happen after the server
 * acted. 401 and 403 mean the API key or account is wrong, so every order would fail the same way; those must stop the
 * agent, not turn into a stream of rejected entries.
 */
function isDefinitiveRefusal(status: number): boolean {
  return status >= 400 && status < 500 && ![401, 403, 408, 429].includes(status);
}

function parseOrder(body: unknown): PaperOrder {
  const record = asRecord(body);
  const status = String(record['status'] ?? 'unknown');
  return {
    id: Number(record['id']),
    clientOrderId: typeof record['client_order_id'] === 'string' ? record['client_order_id'] : undefined,
    status: (KNOWN_STATUSES.has(status) ? status : 'unknown') as PaperOrder['status'],
    filledQuantity: Number(record['filled_quantity'] ?? 0),
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

function asArray(value: unknown): unknown[] {
  if (Array.isArray(value)) {
    return value;
  }
  const data = asRecord(value)['data'];
  return Array.isArray(data) ? data : [];
}

function errorText(text: string): string {
  try {
    const message = asRecord(JSON.parse(text))['error'];
    if (typeof message === 'string') {
      return message.slice(0, 200);
    }
  } catch {
    // Not JSON: fall through to the raw text.
  }
  return text.slice(0, 200);
}

function networkMessage(error: unknown): string {
  return error instanceof Error ? error.name : 'unknown error';
}
