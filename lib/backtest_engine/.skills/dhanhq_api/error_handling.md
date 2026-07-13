# Error Handling

Handle:

- Rate limits
- Authentication failures
- Network timeouts
- Broker maintenance
- Invalid instruments
- Partial responses
- Empty datasets
- WebSocket reconnects
- Duplicate events
- Out-of-order events

## Strategy

- Retry with exponential backoff
- Circuit breaker pattern
- Graceful degradation
- Error logging
- Alerting
- Fallback data sources
