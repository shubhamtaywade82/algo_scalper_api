# Testing Strategy

All code examples in this document are Ruby (RSpec).

## The Testing Pyramid

- **Unit tests** (many) — One class or method, fast, isolated. Most tests here.
- **Integration tests** (some) — Multiple components together (e.g. service + repository).
- **E2E / Acceptance** (few) — Full system, slow, critical paths only.

## Arrange-Act-Assert (RSpec)

```ruby
it 'applies discount to premium users' do
  # ARRANGE
  user = User.new(premium: true)
  cart = Cart.new(user)
  cart.add_item(price: 100)

  # ACT
  total = cart.total

  # ASSERT
  expect(total).to eq(80)
end
```

## Test Naming

- **Bad:** `it 'should work'`, `it 'handles edge case'`
- **Good:** `it 'returns 80 when premium user has 100 order'`, `it 'raises when cart is empty'`

Use concrete examples and domain language.

## Test Doubles (RSpec)

- **Double** — Stand-in that responds to messages you expect.
- **Stub** — Predefined return values (`allow().to receive().and_return`).
- **Mock** — Verifies that a message was received (`expect().to receive()`).

Use real objects when possible; doubles for external dependencies (DB, HTTP, etc.).

## Testing by Layer

- **Domain** — Unit test value objects and entities; no mocks.
- **Application** — Integration tests with fake or in-memory repositories.
- **Infrastructure** — Integration tests with real DB or adapters where needed.

## Common Mistakes

- Testing implementation instead of behavior
- Too many mocks (tests prove nothing)
- Shared state between examples — keep each example isolated
