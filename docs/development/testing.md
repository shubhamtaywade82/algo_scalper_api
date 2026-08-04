# Better Specs Guidelines

This document outlines the Better Specs best practices we follow for testing in the Algo Scalper API project.

Source: https://www.betterspecs.org/

## Key Principles

### 1. Describe Your Methods
Use Ruby documentation conventions:
- `.` or `::` for class methods
- `#` for instance methods

**Example:**
```ruby
describe '.authenticate' do
describe '#admin?' do
```

### 2. Use Contexts
Always use contexts to organize tests. Start context descriptions with:
- `when`
- `with` / `without`
- `if` / `unless`
- `for`
- `that`

**Example:**
```ruby
context 'when logged in' do
  it { is_expected.to respond_with 200 }
end

context 'when logged out' do
  it { is_expected.to respond_with 401 }
end
```

### Test Tooling

- **RSpec** — test framework
- **FactoryBot** — test data factories
- **VCR** — records/replays DhanHQ HTTP/WebSocket interactions
- **Timecop** — time manipulation for time-regime guards, time-stop tests

---

## Paper Trading Validation

The primary validation approach is running with **`LIVE_TRADING` unset or false** (paper gateway forced), optional **`SIGNAL_TIER=exploratory`** for a permissive preset overlay, and `dhanhq.enable_orders: false` / no `PLACE_ORDER` while you prove the stack. All market data is real (live DhanHQ WebSocket); order execution is simulated in paper mode.

### Quick Pre-Session Checks

```bash
# Verify base paper_trading block (effective mode also depends on LIVE_TRADING)
grep -A 3 "paper_trading" config/algo.yml

# Verify signal tier (env overrides signals.signal_tier)
grep -A 2 "signal_tier" config/algo.yml

# Verify risk parameters
grep -A 10 "^risk:" config/algo.yml
```

**Good:**
```ruby
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

### 4. Single Expectation
Each test should make only one assertion for isolated unit tests.

**Good (isolated):**
```ruby
it { is_expected.to respond_with_content_type(:json) }
it { is_expected.to assign_to(:resource) }
```

**Good (not isolated - integration tests):**
```ruby
it 'creates a resource' do
  expect(response).to respond_with_content_type(:json)
  expect(response).to assign_to(:resource)
end
```

### 5. Test All Possible Cases
Test valid, edge, and invalid cases.

**Example:**
```ruby
describe '#destroy' do
  context 'when resource is found' do
    it 'responds with 200'
    it 'shows the resource'
  end

  context 'when resource is not found' do
    it 'responds with 404'
  end

  context 'when resource is not owned' do
    it 'responds with 404'
  end
end
```

### 6. Use Expect Syntax (Not Should)
Always use `expect` syntax, not `should`.

**Bad:**
```ruby
it 'creates a resource' do
  response.should respond_with_content_type(:json)
end
```

**Good:**
```ruby
it 'creates a resource' do
  expect(response).to respond_with_content_type(:json)
end
```

For implicit subject use `is_expected.to`:
```ruby
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

### 7. Use Subject
Use `subject` to DRY up tests related to the same subject.

## Signal Tiers And Tuning (No `run_mode`)

`RUN_MODE`, `exit_testing`, and `config/profiles/*.yml` are **removed**. See
`docs/development/testing_profiles.md` for the historical note.

| Goal | What to use |
|------|-------------|
| More permissive signal YAML overlay | `SIGNAL_TIER=exploratory` or set `signals.signal_tier: exploratory` |
| Match `algo.yml` as merged with DB only | `SIGNAL_TIER=standard` (default when tier invalid/missing) |
| Stricter preset overlay | `SIGNAL_TIER=selective` |
| Stress entry or exit plumbing | Tune `signals.*`, guards, and risk blocks in YAML or DB overrides — same code path for all |

```bash
# Example: exploratory tier + paper gateway (LIVE_TRADING unset)
SIGNAL_TIER=exploratory ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

**Good:**
```ruby
describe '#type_id' do
  let(:resource) { FactoryBot.create :device }
  let(:type)     { Type.find resource.type_id }
  it 'sets the type_id field' do
    expect(resource.type_id).to eq(type.id)
  end
end
```

### 9. Don't Overuse Mocks
As a general rule, don't (over)use mocks. Test real behavior when possible.

### 10. Create Only the Data You Need
Don't load more data than needed for your tests.

**Good:**
```ruby
describe ".top" do
  before { FactoryBot.create_list(:user, 3) }
  it { expect(User.top(2)).to have(2).item }
end
```

### 11. Use Factories (Not Fixtures)
Use Factory Bot to reduce verbosity when creating test data.

**Bad:**
```ruby
user = User.create(
  name: 'Genoveffa',
  surname: 'Piccolina',
  city: 'Billyville',
  birth: '17 Agoust 1982',
  active: true
)
```

**Good:**
```ruby
user = FactoryBot.create :user
```

### 12. Use Easy-to-Read Matchers
Use readable matchers from RSpec.

**Bad:**
```ruby
lambda { model.save! }.to raise_error Mongoid::Errors::DocumentNotFound
```

**Good:**
```ruby
expect { model.save! }.to raise_error Mongoid::Errors::DocumentNotFound
```

### 13. Don't Use "Should"
Do not use "should" in test descriptions. Use third person present tense.

**Bad:**
```ruby
it 'should not change timings' do
  consumption.occur_at.should == valid.occur_at
end
```

**Good:**
```ruby
it 'does not change timings' do
  expect(consumption.occur_at).to eq(valid.occur_at)
end
```

## Configuration

Our `.rubocop.yml` enforces these guidelines with the following cops:

- `RSpec/ContextWording`: Enforces contexts starting with `when`, `with`, `without`, etc.
- `RSpec/SingleExpectation`: Enforced for unit tests, relaxed for integration/system tests
- `RSpec/NestedGroups`: Max 5 levels deep
- `RSpec/MultipleMemoizedHelpers`: Max 10 helpers
- `Layout/LineLength`: Max 120 characters with specific exclusions

## Additional Resources

- [Better Specs Website](https://www.betterspecs.org/)
- [RSpec Documentation](https://rspec.info/)
- [Factory Bot Documentation](https://github.com/thoughtbot/factory_bot)

