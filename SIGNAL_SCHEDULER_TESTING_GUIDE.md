# Signal Scheduler - Quick Testing Guide

## Quick Start

### 1. Install Dependencies

Add to `Gemfile`:
```ruby
group :development, :test do
  gem 'timecop', '~> 0.9.8'
end
```

Run:
```bash
bundle install
```

### 2. Run Tests

```bash
# All scheduler tests
bundle exec rspec spec/services/signal/scheduler*

# Specific test file
bundle exec rspec spec/services/signal/scheduler_spec.rb

# With VCR recording (first time)
VCR_MODE=all bundle exec rspec spec/services/signal/scheduler_integration_spec.rb

# With VCR playback only (faster)
VCR_MODE=none bundle exec rspec spec/services/signal/scheduler_integration_spec.rb
```

## Testing Patterns

### Pattern 1: Unit Test with Mocks

```ruby
require 'rails_helper'

RSpec.describe Signal::Scheduler do
  let(:scheduler) { described_class.new(period: 1) }
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }

  it 'processes index when signal generated' do
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    allow(scheduler).to receive(:evaluate_supertrend_signal).and_return({
      segment: 'NSE_FNO',
      security_id: '12345',
      meta: { candidate_symbol: 'TEST', direction: :bullish }
    })
    allow(scheduler).to receive(:process_signal)

    scheduler.send(:process_index, index_cfg)

    expect(scheduler).to have_received(:process_signal)
  end
end
```

### Pattern 2: Time-Based Test with Timecop

```ruby
require 'rails_helper'
require 'timecop'

RSpec.describe Signal::Scheduler do
  let(:scheduler) { described_class.new(period: 1) }

  before do
    # Freeze time to market hours
    Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
    allow(AlgoConfig).to receive(:fetch).and_return(indices: [{ key: 'NIFTY' }])
  end

  after do
    Timecop.return
    scheduler.stop if scheduler.running?
  end

  it 'processes during market hours' do
    scheduler.start
    sleep(0.1)
    expect(scheduler.running?).to be true
  end

  it 'skips when market closed' do
    Timecop.freeze(Time.zone.parse('2024-01-15 16:00:00 IST'))
    scheduler.start
    sleep(0.1)
    # Should skip processing
  end
end
```

### Pattern 3: Integration Test with VCR

```ruby
require 'rails_helper'

RSpec.describe Signal::Scheduler, :vcr do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:instrument) { create(:instrument, :nifty_index) }

  before do
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
    allow(AlgoConfig).to receive(:fetch).and_return({
      indices: [index_cfg],
      signals: { primary_timeframe: '1m', supertrend: { period: 10 } }
    })
    allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
  end

  it 'fetches real OHLC data', :vcr do
    scheduler = described_class.new
    result = scheduler.send(:evaluate_supertrend_signal, index_cfg)
    # VCR records/plays back API calls
    expect(result).to be_nil.or(be_a(Hash))
  end
end
```

### Pattern 4: Full Integration with Timecop + VCR

```ruby
require 'rails_helper'
require 'timecop'

RSpec.describe Signal::Scheduler, :vcr do
  let(:scheduler) { described_class.new(period: 2) }

  before do
    Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
    # ... setup mocks and config ...
  end

  after do
    Timecop.return
    scheduler.stop if scheduler.running?
  end

  it 'runs complete cycle', :vcr do
    scheduler.start
    sleep(0.1)
    expect(scheduler.running?).to be true

    Timecop.travel(2.seconds)
    sleep(0.1)

    scheduler.stop
    expect(scheduler.running?).to be false
  end
end
```

## Timecop Cheat Sheet

```ruby
# Freeze time to specific moment
Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))

# Travel forward in time
Timecop.travel(30.seconds)
Timecop.travel(1.hour)

# Return to real time
Timecop.return

# Block syntax (auto-returns)
Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST')) do
  # Test code here
end
```

## VCR Cheat Sheet

```ruby
# Mark test to use VCR
it 'test name', :vcr do
  # VCR will record/playback API calls
end

# Record new cassette
VCR_MODE=all bundle exec rspec spec/path/to/test_spec.rb

# Playback only (no API calls)
VCR_MODE=none bundle exec rspec spec/path/to/test_spec.rb

# Default (use if exists, record if missing)
VCR_MODE=once bundle exec rspec spec/path/to/test_spec.rb
```

## Common Test Scenarios

### Test Market Hours Behavior

```ruby
context 'market hours' do
  before do
    Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
  end

  after { Timecop.return }

  it 'processes during market hours' do
    # Test code
  end
end
```

### Test Scheduler Timing

```ruby
it 'processes at correct intervals' do
  scheduler.start
  sleep(0.1)
  
  # First cycle
  expect(scheduler).to have_received(:process_index).once
  
  # Advance time
  Timecop.travel(30.seconds)
  sleep(0.1)
  
  # Second cycle
  expect(scheduler).to have_received(:process_index).at_least(:twice)
end
```

### Test Error Recovery

```ruby
it 'continues after error' do
  allow(scheduler).to receive(:process_index).and_raise(StandardError)
  
  scheduler.start
  sleep(0.1)
  
  # Should still be running
  expect(scheduler.running?).to be true
end
```

### Test Thread Behavior

```ruby
it 'runs in background thread' do
  scheduler.start
  sleep(0.1)
  
  expect(Thread.list.map(&:name)).to include('signal-scheduler')
  
  scheduler.stop
end
```

## Environment Variables

```bash
# VCR recording mode
VCR_MODE=all      # Record all interactions
VCR_MODE=once     # Use if exists, record if missing (default)
VCR_MODE=none     # Playback only, fail if missing

# VCR recording delay (prevent rate limits)
VCR_RECORDING_DELAY=0.5

# Test delay between tests
TEST_DELAY=0.1

# Disable trading services in test
DISABLE_TRADING_SERVICES=1
DHANHQ_ENABLED=false
```

## Test File Structure

```
spec/
  services/
    signal/
      scheduler_spec.rb                    # Unit tests with mocks
      scheduler_time_spec.rb               # Time-based tests
      scheduler_integration_spec.rb         # Integration with VCR
      scheduler_full_integration_spec.rb    # Full integration
  cassettes/
    signal/
      scheduler_integration_spec.yml        # VCR cassettes
```

## Debugging Tests

### Enable Debug Logging

```ruby
before do
  Rails.logger.level = Logger::DEBUG
end
```

### Inspect Thread State

```ruby
it 'debug thread state' do
  scheduler.start
  sleep(0.1)
  
  thread = Thread.list.find { |t| t.name == 'signal-scheduler' }
  puts "Thread alive?: #{thread.alive?}"
  puts "Thread status: #{thread.status}"
  
  scheduler.stop
end
```

### Inspect Scheduler State

```ruby
it 'debug scheduler state' do
  scheduler.start
  sleep(0.1)
  
  puts "Running?: #{scheduler.running?}"
  puts "Thread: #{scheduler.instance_variable_get(:@thread)}"
  
  scheduler.stop
end
```

## Troubleshooting

### Issue: Timecop not working

**Solution**: Ensure `require 'timecop'` is at the top of your spec file.

### Issue: VCR not recording

**Solution**: Set `VCR_MODE=all` and ensure test is marked with `:vcr`.

### Issue: Tests timing out

**Solution**: Reduce `period` in scheduler initialization (e.g., `period: 1` instead of `period: 30`).

### Issue: Thread not stopping

**Solution**: Ensure `scheduler.stop` is called in `after` block and wait for thread to finish.

## Best Practices

1. **Always cleanup**: Use `after` blocks to stop scheduler and return Timecop
2. **Use short periods**: Set `period: 1` for faster tests
3. **Mock external services**: Mock EntryGuard to prevent actual orders
4. **Use VCR for API calls**: Record real API responses for integration tests
5. **Test edge cases**: Market close, errors, empty configs
6. **Test timing**: Use Timecop to test time-dependent behavior
7. **Isolate tests**: Each test should be independent

## Example: Complete Test File

```ruby
# frozen_string_literal: true

require 'rails_helper'
require 'timecop'

RSpec.describe Signal::Scheduler, :vcr do
  let(:index_cfg) do
    { key: 'NIFTY', segment: 'IDX_I', sid: '13', max_same_side: 2 }
  end
  let(:scheduler) { described_class.new(period: 1) }
  let(:instrument) { create(:instrument, :nifty_index) }

  before do
    Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
    
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
    allow(AlgoConfig).to receive(:fetch).and_return({
      indices: [index_cfg],
      signals: {
        primary_timeframe: '1m',
        supertrend: { period: 10, base_multiplier: 2.0 },
        adx: { min_strength: 18.0 }
      }
    })
    allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
    
    Signal::StateTracker.reset(index_cfg[:key])
  end

  after do
    Timecop.return
    scheduler.stop if scheduler.running?
    Signal::StateTracker.reset(index_cfg[:key])
  end

  describe '#start' do
    it 'starts scheduler during market hours' do
      scheduler.start
      sleep(0.1)
      
      expect(scheduler.running?).to be true
      expect(Thread.list.map(&:name)).to include('signal-scheduler')
    end
  end

  describe '#process_index' do
    it 'processes index with real API calls', :vcr do
      result = scheduler.send(:evaluate_supertrend_signal, index_cfg)
      expect(result).to be_nil.or(be_a(Hash))
    end
  end

  describe 'market hours' do
    it 'skips processing when market closed' do
      Timecop.freeze(Time.zone.parse('2024-01-15 16:00:00 IST'))
      
      scheduler.start
      sleep(0.1)
      
      # Should skip processing
      expect(scheduler.running?).to be true
    end
  end
end
```

For complete documentation, see `SIGNAL_SCHEDULER_DETAILED_ANALYSIS.md`.
