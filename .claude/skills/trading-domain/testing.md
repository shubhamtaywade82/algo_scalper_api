# Trading Domain Testing Guide

## Test Pyramid for Trading Applications

1. **Unit (Fast, Pure Ruby, No Rails)**:
   - `domain/` entities and state machines
   - Risk rules (`MaxPositionSize`, `MaxDailyLoss`)
   - PnL and margin calculators
   - Value objects

2. **Integration (Rails Loaded, DB Ready, Mocked Gateways)**:
   - `services/` (`Orders::Place`, `Positions::Close`)
   - `models/` ActiveRecord validations & scopes
   - `jobs/` with inline queue adapter

3. **Contract Specs (Mocked HTTP / WebMock / VCR)**:
   - `gateways/brokers/` using shared RSpec example contracts

4. **Idempotency Specs**:
   - Webhook callback deduplication tests

---

## Example RSpec Contract for Gateway Adapters

```ruby
RSpec.shared_examples "a broker gateway" do
  describe "#place_order" do
    it "returns a BrokerResponse with broker_order_id" do
      response = gateway.place_order(valid_order_params)
      expect(response).to be_a(BrokerResponse)
      expect(response.broker_order_id).to be_present
    end
  end

  describe "#get_positions" do
    it "returns array of BrokerPosition objects" do
      positions = gateway.get_positions
      expect(positions).to all(be_a(BrokerPosition))
    end
  end
end
```
