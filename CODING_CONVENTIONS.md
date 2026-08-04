# Coding Conventions - Algo Scalper API

**Strict, enforceable rules for code generation and refactoring.**

All rules use imperative language (Always/Never, Do/Don't) and include examples for validation.

---

## Rails Backend Rules

### File Organization

#### RULE: Always start Ruby files with frozen_string_literal
**DO:**
```ruby
# frozen_string_literal: true

class MyService
end
```

**DON'T:**
```ruby
class MyService
end
```

#### RULE: Always place controllers under app/controllers/api/ with Api:: namespace
**DO:**
```ruby
# app/controllers/api/health_controller.rb
# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
  end
end
```

**DON'T:**
```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
end
```

#### RULE: Always organize services by domain in app/services/domain/ subdirectories
**DO:**
```
app/services/
  signal/
    engine.rb
  options/
    chain_analyzer.rb
  capital/
    allocator.rb
```

**DON'T:**
```
app/services/
  signal_engine.rb
  options_chain_analyzer.rb
  capital_allocator.rb
```

#### RULE: Always place models in app/models/ with concerns in app/models/concerns/
**DO:**
```
app/models/
  instrument.rb
  concerns/
    instrument_helpers.rb
```

**DON'T:**
```
app/models/
  instrument.rb
  instrument_helpers.rb
```

#### RULE: Always place shared utilities in lib/, never in app/
**DO:**
```
lib/
  providers/
    dhanhq_provider.rb
  services/
    option_chain_cache.rb
```

**DON'T:**
```
app/
  providers/
    dhanhq_provider.rb
```

### Service Patterns

#### RULE: Always inherit from TradingSystem::BaseService for services with lifecycle (start/stop)
**DO:**
```ruby
# frozen_string_literal: true

module TradingSystem
  class OrderRouter < BaseService
    def start
      Rails.logger.info("[OrderRouter] ready")
      true
    end

    def stop
      Rails.logger.info("[OrderRouter] stopped")
      true
    end
  end
end
```

**DON'T:**
```ruby
class OrderRouter
  def start
  end
end
```

#### RULE: Always inherit from ApplicationService for stateless utility services
**DO:**
```ruby
# frozen_string_literal: true

module Options
  class ExpiredFetcher < ApplicationService
    def self.call(expiry_date:)
      new(expiry_date: expiry_date).call
    end

    def call
      # implementation
    end
  end
end
```

**DON'T:**
```ruby
class ExpiredFetcher
  def self.call
  end
end
```

#### RULE: Always use include Singleton for services managing global state
**DO:**
```ruby
# frozen_string_literal: true

module Live
  class MarketFeedHub
    include Singleton

    def running?
      @running ||= false
    end
  end
end

# Usage: Live::MarketFeedHub.instance.running?
```

**DON'T:**
```ruby
class MarketFeedHub
  def self.instance
    @instance ||= new
  end
end
```

#### RULE: Always access singleton services via .instance class method
**DO:**
```ruby
Live::MarketFeedHub.instance.running?
Live::RiskManagerService.instance.update_pnl(tracker_id: 1, pnl: 100.0)
```

**DON'T:**
```ruby
MarketFeedHub.new.running?
RiskManagerService.new.update_pnl(tracker_id: 1, pnl: 100.0)
```

#### RULE: Always organize services by domain: signal/, options/, capital/, entries/, orders/, live/, risk/, indicators/
**DO:**
```
app/services/
  signal/
    engine.rb
  options/
    chain_analyzer.rb
  live/
    market_feed_hub.rb
```

**DON'T:**
```
app/services/
  signal_engine.rb
  options_chain_analyzer.rb
  live_market_feed_hub.rb
```

### Controller Patterns

#### RULE: Always inherit controllers from ApplicationController < ActionController::API
**DO:**
```ruby
# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
    def show
      render json: { status: 'ok' }
    end
  end
end
```

**DON'T:**
```ruby
class HealthController < ActionController::Base
end
```

#### RULE: Never put business logic in controllers - always delegate to services
**DO:**
```ruby
def show
  result = Signal::Engine.run_for(index_cfg)
  render json: { result: result }
end
```

**DON'T:**
```ruby
def show
  instrument = Instrument.find_by(symbol_name: 'NIFTY')
  candles = instrument.candle_series(interval: '5')
  # ... complex business logic here ...
  render json: { result: analysis }
end
```

#### RULE: Always use render json: for API responses, never use serializers
**DO:**
```ruby
def show
  render json: {
    mode: AlgoConfig.mode,
    watchlist: WatchlistItem.where(active: true).count
  }
end
```

**DON'T:**
```ruby
def show
  render json: HealthSerializer.new(status).as_json
end
```

#### RULE: Always namespace controllers under Api:: module
**DO:**
```ruby
module Api
  class HealthController < ApplicationController
  end
end
```

**DON'T:**
```ruby
class HealthController < ApplicationController
end
```

### Model Patterns

#### RULE: Always inherit models from ApplicationRecord < ActiveRecord::Base
**DO:**
```ruby
# frozen_string_literal: true

class Instrument < ApplicationRecord
end
```

**DON'T:**
```ruby
class Instrument < ActiveRecord::Base
end
```

#### RULE: Always use concerns for shared model logic in app/models/concerns/
**DO:**
```ruby
# app/models/instrument.rb
class Instrument < ApplicationRecord
  include InstrumentHelpers
end

# app/models/concerns/instrument_helpers.rb
module InstrumentHelpers
  extend ActiveSupport::Concern
  # shared logic
end
```

**DON'T:**
```ruby
class Instrument < ApplicationRecord
  def ltp
    # shared logic duplicated
  end
end

class Derivative < ApplicationRecord
  def ltp
    # same logic duplicated
  end
end
```

#### RULE: Always use enum for status/type fields, never string constants
**DO:**
```ruby
class PositionTracker < ApplicationRecord
  enum :status, { pending: 'pending', active: 'active', exited: 'exited', cancelled: 'cancelled' }
end
```

**DON'T:**
```ruby
class PositionTracker < ApplicationRecord
  STATUS_PENDING = 'pending'
  STATUS_ACTIVE = 'active'
end
```

#### RULE: Always define scopes as class methods
**DO:**
```ruby
class PositionTracker < ApplicationRecord
  scope :active, -> { where(status: 'active') }
end
```

**DON'T:**
```ruby
class PositionTracker < ApplicationRecord
  def self.active
    where(status: 'active')
  end
end
```

#### RULE: Always specify dependent: options for associations
**DO:**
```ruby
class Instrument < ApplicationRecord
  has_many :derivatives, dependent: :destroy
  has_many :position_trackers, dependent: :restrict_with_error
end
```

**DON'T:**
```ruby
class Instrument < ApplicationRecord
  has_many :derivatives
  has_many :position_trackers
end
```

### Code Style

#### RULE: Always use 2 spaces for indentation, never tabs
**DO:**
```ruby
def method
  if condition
    do_something
  end
end
```

**DON'T:**
```ruby
def method
	if condition
		do_something
	end
end
```

#### RULE: Never exceed 120 characters per line (exceptions: comments, describe/context/it/expect)
**DO:**
```ruby
result = Signal::Engine.run_for(
  index_cfg: index_cfg,
  instrument: instrument,
  timeframe: '5m'
)
```

**DON'T:**
```ruby
result = Signal::Engine.run_for(index_cfg: index_cfg, instrument: instrument, timeframe: '5m', supertrend_cfg: supertrend_cfg, adx_min_strength: adx_min_strength)
```

#### RULE: Never exceed 30 lines per method (exceptions: spec files)
**DO:**
```ruby
def calculate_pnl
  entry_value = entry_price * quantity
  current_value = current_price * quantity
  entry_value - current_value
end
```

**DON'T:**
```ruby
def calculate_pnl
  # 50+ lines of complex logic
end
```

#### RULE: Always pass RuboCop checks before commit
**DO:**
```bash
bin/rubocop
# Fix all offenses before committing
```

**DON'T:**
```bash
# Commit code with RuboCop offenses
git commit -m "Add feature"
```

---

## Database Rules

### Migrations

#### RULE: Always name migration files with timestamp prefix: YYYYMMDDHHMMSS_descriptive_name.rb
**DO:**
```
db/migrate/20251004062009_create_instruments.rb
db/migrate/20251105042636_add_watchable_to_position_trackers.rb
```

**DON'T:**
```
db/migrate/create_instruments.rb
db/migrate/add_watchable.rb
```

#### RULE: Always use ActiveRecord::Migration[8.0] version
**DO:**
```ruby
class CreateInstruments < ActiveRecord::Migration[8.0]
  def change
  end
end
```

**DON'T:**
```ruby
class CreateInstruments < ActiveRecord::Migration[7.0]
end
```

#### RULE: Always use def change method, never up/down unless necessary
**DO:**
```ruby
class CreateInstruments < ActiveRecord::Migration[8.0]
  def change
    create_table :instruments do |t|
      t.string :symbol_name
      t.timestamps
    end
  end
end
```

**DON'T:**
```ruby
class CreateInstruments < ActiveRecord::Migration[8.0]
  def up
    create_table :instruments
  end

  def down
    drop_table :instruments
  end
end
```

#### RULE: Always add indexes with descriptive names
**DO:**
```ruby
add_index :instruments, :symbol_name, name: 'index_instruments_on_symbol_name'
add_index :instruments, %i[security_id symbol_name exchange segment],
  unique: true, name: 'index_instruments_unique'
```

**DON'T:**
```ruby
add_index :instruments, :symbol_name
add_index :instruments, [:security_id, :symbol_name]
```

#### RULE: Always use where: clause for partial indexes filtering NULL values
**DO:**
```ruby
add_index :instruments, %i[underlying_symbol expiry_date],
  where: 'underlying_symbol IS NOT NULL'
```

**DON'T:**
```ruby
add_index :instruments, %i[underlying_symbol expiry_date]
```

### Schema Design

#### RULE: Always include created_at and updated_at timestamps in all tables
**DO:**
```ruby
create_table :instruments do |t|
  t.string :symbol_name
  t.timestamps
end
```

**DON'T:**
```ruby
create_table :instruments do |t|
  t.string :symbol_name
end
```

#### RULE: Always specify precision and scale for decimal columns
**DO:**
```ruby
t.decimal :strike_price, precision: 15, scale: 5
t.decimal :buy_co_min_margin_per, precision: 8, scale: 2
```

**DON'T:**
```ruby
t.decimal :strike_price
t.decimal :buy_co_min_margin_per
```

#### RULE: Always explicitly add foreign keys with add_foreign_key
**DO:**
```ruby
add_foreign_key :derivatives, :instruments
add_foreign_key :paper_positions, :instruments
```

**DON'T:**
```ruby
# Relying on t.references without explicit foreign key
t.references :instrument
```

#### RULE: Always specify null: false for required fields
**DO:**
```ruby
t.string :exchange, null: false
t.string :segment, null: false
t.string :security_id, null: false
```

**DON'T:**
```ruby
t.string :exchange
t.string :segment
t.string :security_id
```

#### RULE: Always specify default values for status fields and numeric columns
**DO:**
```ruby
t.string :status, default: 'pending', null: false
t.decimal :total_pnl, precision: 15, scale: 2, default: '0.0', null: false
t.integer :trades_count, default: 0, null: false
```

**DON'T:**
```ruby
t.string :status
t.decimal :total_pnl
t.integer :trades_count
```

#### RULE: Always use JSONB columns for flexible metadata (meta, metadata)
**DO:**
```ruby
t.jsonb :meta, default: {}, null: false
t.jsonb :metadata, default: {}, null: false
```

**DON'T:**
```ruby
t.text :meta
t.json :metadata
```

#### RULE: Always use _type and _id suffix pattern for polymorphic associations
**DO:**
```ruby
t.string :watchable_type, null: false
t.bigint :watchable_id, null: false
```

**DON'T:**
```ruby
t.string :entity_type
t.bigint :entity_id
```

### Indexing

#### RULE: Always enforce unique constraints via composite unique indexes
**DO:**
```ruby
add_index :instruments, %i[security_id symbol_name exchange segment],
  unique: true, name: 'index_instruments_unique'
```

**DON'T:**
```ruby
# Using database-level unique constraint without index name
t.index [:security_id, :symbol_name, :exchange, :segment], unique: true
```

#### RULE: Always use GIN indexes for JSONB columns that are queried
**DO:**
```ruby
add_index :trading_signals, :metadata, using: :gin
```

**DON'T:**
```ruby
add_index :trading_signals, :metadata
```

#### RULE: Always create composite indexes for common multi-column queries
**DO:**
```ruby
add_index :position_trackers, %i[status security_id]
add_index :trading_signals, %i[index_key signal_timestamp]
```

**DON'T:**
```ruby
# Only single column indexes
add_index :position_trackers, :status
add_index :position_trackers, :security_id
```

---

## Testing Rules (RSpec)

### Test Structure

#### RULE: Always name test files *_spec.rb and place in spec/ directory
**DO:**
```
spec/
  models/
    instrument_spec.rb
  services/
    signal/
      engine_spec.rb
```

**DON'T:**
```
test/
  models/
    instrument_test.rb
spec/
  instrument.rb
```

#### RULE: Always mirror app/ directory structure in spec/
**DO:**
```
app/services/signal/engine.rb
spec/services/signal/engine_spec.rb
```

**DON'T:**
```
app/services/signal/engine.rb
spec/engine_spec.rb
```

#### RULE: Always require rails_helper.rb in test files
**DO:**
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instrument do
end
```

**DON'T:**
```ruby
require 'spec_helper'

RSpec.describe Instrument do
end
```

#### RULE: Always use FactoryBot for test data creation
**DO:**
```ruby
let(:instrument) { create(:instrument, :nifty_index) }
let(:position) { create(:position_tracker, instrument: instrument) }
```

**DON'T:**
```ruby
let(:instrument) do
  Instrument.create!(
    security_id: '13',
    symbol_name: 'NIFTY',
    exchange: 'nse',
    segment: 'index'
  )
end
```

### RSpec Patterns

#### RULE: Always use . or :: for class methods, # for instance methods in describe blocks
**DO:**
```ruby
RSpec.describe Signal::Engine do
  describe '.run_for' do
    # class method test
  end

  describe '#analyze_timeframe' do
    # instance method test
  end
end
```

**DON'T:**
```ruby
RSpec.describe Signal::Engine do
  describe 'run_for' do
  end

  describe 'analyze_timeframe' do
  end
end
```

#### RULE: Always start context blocks with: when, with, without, if, unless, for, that
**DO:**
```ruby
context 'when instrument is found' do
end

context 'with valid parameters' do
end

context 'without confirmation timeframe' do
end
```

**DON'T:**
```ruby
context 'instrument is found' do
end

context 'valid parameters' do
end
```

#### RULE: Never exceed 40 characters in spec descriptions - split using contexts
**DO:**
```ruby
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

**DON'T:**
```ruby
it 'has 422 status code if an unexpected params will be added' do
end
```

#### RULE: Never exceed 5 levels of nested describe/context blocks
**DO:**
```ruby
RSpec.describe Signal::Engine do
  describe '.run_for' do
    context 'when instrument is found' do
      context 'with valid timeframe' do
        it 'generates signal' do
        end
      end
    end
  end
end
```

**DON'T:**
```ruby
# 6+ levels of nesting
```

#### RULE: Never exceed 25 lines per example (exceptions: features, integration, system specs)
**DO:**
```ruby
it 'creates a resource' do
  result = described_class.call(params)
  expect(result).to be_success
end
```

**DON'T:**
```ruby
it 'creates a resource' do
  # 30+ lines of setup and assertions
end
```

#### RULE: Always use expect syntax, never should syntax
**DO:**
```ruby
expect(result).to be_success
expect(response).to have_http_status(:ok)
```

**DON'T:**
```ruby
result.should be_success
response.should have_http_status(:ok)
```

### Test Data

#### RULE: Always define factories in spec/factories/ directory
**DO:**
```
spec/factories/
  instruments.rb
  position_trackers.rb
```

**DON'T:**
```
spec/
  factories.rb
  test_data.rb
```

#### RULE: Always define factory attributes statically
**DO:**
```ruby
FactoryBot.define do
  factory :instrument do
    sequence(:security_id) { |n| (10_000 + n).to_s }
    symbol_name { 'NIFTY' }
    exchange { 'nse' }
  end
end
```

**DON'T:**
```ruby
FactoryBot.define do
  factory :instrument do
    security_id { generate(:security_id) }
    symbol_name { generate(:symbol_name) }
  end
end
```

#### RULE: Always use traits for factory variations
**DO:**
```ruby
factory :instrument do
  trait :nifty_index do
    security_id { '13' }
    symbol_name { 'NIFTY' }
  end

  trait :banknifty_index do
    security_id { '25' }
    symbol_name { 'BANKNIFTY' }
  end
end

# Usage: create(:instrument, :nifty_index)
```

**DON'T:**
```ruby
factory :nifty_instrument do
  security_id { '13' }
end

factory :banknifty_instrument do
  security_id { '25' }
end
```

#### RULE: Always use VCR for external API call recording/playback
**DO:**
```ruby
RSpec.describe Signal::Engine, :vcr do
  it 'fetches OHLC data' do
    # VCR will record/playback API calls
  end
end
```

**DON'T:**
```ruby
RSpec.describe Signal::Engine do
  it 'fetches OHLC data' do
    # Makes real API calls every time
  end
end
```

#### RULE: Always disable DhanHQ in test environment
**DO:**
```ruby
# spec/rails_helper.rb
ENV['DHANHQ_ENABLED'] ||= 'false'
ENV['DHANHQ_WS_ENABLED'] ||= 'false'
```

**DON'T:**
```ruby
# Making real API calls in tests
```

---

## API Design Rules

### Endpoints

#### RULE: Always place all API endpoints under /api namespace
**DO:**
```ruby
# config/routes.rb
namespace :api do
  get :health, to: 'health#show'
end
```

**DON'T:**
```ruby
get :health, to: 'health#show'
```

#### RULE: Always use render json: for all API responses
**DO:**
```ruby
def show
  render json: {
    mode: AlgoConfig.mode,
    status: 'ok'
  }
end
```

**DON'T:**
```ruby
def show
  render json: HealthSerializer.new(status)
end
```

#### RULE: Always use inline hash construction in controllers
**DO:**
```ruby
render json: {
  mode: AlgoConfig.mode,
  watchlist: WatchlistItem.where(active: true).count,
  active_positions: PositionTracker.active.count
}
```

**DON'T:**
```ruby
data = {}
data[:mode] = AlgoConfig.mode
data[:watchlist] = WatchlistItem.where(active: true).count
render json: data
```

---

## Error Handling Rules

### Exception Handling

#### RULE: Always rescue StandardError explicitly, never bare rescue
**DO:**
```ruby
begin
  result = external_api.call
rescue StandardError => e
  Rails.logger.error("[Service] Error: #{e.class} - #{e.message}")
  nil
end
```

**DON'T:**
```ruby
begin
  result = external_api.call
rescue => e
  nil
end
```

#### RULE: Always log errors with class context in brackets
**DO:**
```ruby
Rails.logger.error("[Signal::Engine] Analysis failed: #{e.class} - #{e.message}")
Rails.logger.error("[Orders::Placer] BUY failed: #{e.class} - #{e.message}")
```

**DON'T:**
```ruby
Rails.logger.error("Analysis failed: #{e.message}")
Rails.logger.error("Error: #{e}")
```

#### RULE: Always include exception class and message in error logs
**DO:**
```ruby
Rails.logger.error("[Service] Error: #{e.class} - #{e.message}")
```

**DON'T:**
```ruby
Rails.logger.error("[Service] Error: #{e.message}")
Rails.logger.error("[Service] Error occurred")
```

#### RULE: Always return nil or error hash on failure, never raise to callers
**DO:**
```ruby
def fetch_data
  external_api.call
rescue StandardError => e
  Rails.logger.error("[Service] Error: #{e.class} - #{e.message}")
  nil
end
```

**DON'T:**
```ruby
def fetch_data
  external_api.call
rescue StandardError => e
  raise e  # Don't re-raise to callers
end
```

#### RULE: Always define custom errors as classes inheriting from StandardError
**DO:**
```ruby
module Live
  class FeedHealthService
    FeedStaleError = Class.new(StandardError) do
      attr_reader :feed, :last_seen_at, :threshold

      def initialize(feed:, last_seen_at:, threshold:)
        @feed = feed
        @last_seen_at = last_seen_at
        @threshold = threshold
        super("#{feed} feed stale")
      end
    end
  end
end
```

**DON'T:**
```ruby
def check_feed
  raise "Feed stale" if stale?
end
```

### Retry Logic

#### RULE: Always define maximum retry count as a constant
**DO:**
```ruby
class OrderRouter
  RETRY_COUNT = 3
  RETRY_BASE_SLEEP = 0.2

  def with_retries
    attempts = 0
    begin
      attempts += 1
      yield
    rescue StandardError => e
      raise if attempts >= RETRY_COUNT
      sleep RETRY_BASE_SLEEP * attempts
      retry
    end
  end
end
```

**DON'T:**
```ruby
def with_retries
  attempts = 0
  begin
    attempts += 1
    yield
  rescue StandardError => e
    raise if attempts >= 5  # Magic number
    sleep 0.2
    retry
  end
end
```

---

## Logging Rules

### Log Format

#### RULE: Always include class context in brackets in log messages
**DO:**
```ruby
Rails.logger.info("[Signal::Engine] Starting analysis for NIFTY")
Rails.logger.error("[Orders::Placer] BUY failed: StandardError - Connection timeout")
```

**DON'T:**
```ruby
Rails.logger.info("Starting analysis for NIFTY")
Rails.logger.error("BUY failed")
```

#### RULE: Always use structured format: [ClassName] Action description
**DO:**
```ruby
Rails.logger.info("[Signal::Engine] Starting analysis for #{index_cfg[:key]}")
Rails.logger.warn("[EntryGuard] Cooldown active for #{index_cfg[:key]}")
```

**DON'T:**
```ruby
Rails.logger.info("Starting analysis")
Rails.logger.warn("Cooldown active")
```

#### RULE: Always comment out debug logs in production code
**DO:**
```ruby
# Rails.logger.debug("[Options] Available expiries: #{expiry_list}")
# Rails.logger.debug { "[Options] Using instrument: #{instrument.symbol_name}" }
```

**DON'T:**
```ruby
Rails.logger.debug("[Options] Available expiries: #{expiry_list}")
Rails.logger.debug { "[Options] Using instrument: #{instrument.symbol_name}" }
```

### Log Levels

#### RULE: Always use Rails.logger.info for normal operations
**DO:**
```ruby
Rails.logger.info("[Signal::Engine] Signal generated: bullish")
Rails.logger.info("[Orders::Placer] Order placed: #{order.order_id}")
```

**DON'T:**
```ruby
Rails.logger.debug("[Signal::Engine] Signal generated: bullish")
puts "Order placed: #{order.order_id}"
```

#### RULE: Always use Rails.logger.warn for warnings
**DO:**
```ruby
Rails.logger.warn("[Signal::Engine] Primary timeframe analysis unavailable")
Rails.logger.warn("[EntryGuard] Maximum positions reached")
```

**DON'T:**
```ruby
Rails.logger.info("[Signal::Engine] Primary timeframe analysis unavailable")
Rails.logger.error("[EntryGuard] Maximum positions reached")  # Not an error
```

#### RULE: Always use Rails.logger.error for errors
**DO:**
```ruby
Rails.logger.error("[Signal::Engine] Analysis failed: #{e.class} - #{e.message}")
Rails.logger.error("[Orders::Placer] Order placement failed: #{e.class} - #{e.message}")
```

**DON'T:**
```ruby
Rails.logger.warn("[Signal::Engine] Analysis failed")
puts "Error: #{e.message}"
```

---

## Performance Rules

### Code Performance

#### RULE: Always use start_with?/end_with? instead of regex when possible
**DO:**
```ruby
if key.start_with?('option_chain:')
  # process
end

if filename.end_with?('.rb')
  # process
end
```

**DON'T:**
```ruby
if key =~ /^option_chain:/
  # process
end

if filename =~ /\.rb$/
  # process
end
```

#### RULE: Always use delete_prefix/delete_suffix for string prefix/suffix removal
**DO:**
```ruby
key.delete_prefix('option_chain:')
filename.delete_suffix('.rb')
```

**DON'T:**
```ruby
key.gsub(/^option_chain:/, '')
filename.gsub(/\.rb$/, '')
```

### Caching

#### RULE: Always use descriptive prefixes for cache keys
**DO:**
```ruby
cache_key = "option_chain:#{security_id}:#{expiry}"
cache_key = "tick:#{segment}:#{security_id}"
```

**DON'T:**
```ruby
cache_key = "#{security_id}:#{expiry}"
cache_key = "#{segment}_#{security_id}"
```

#### RULE: Always check cache staleness before use
**DO:**
```ruby
cached_data = Rails.cache.read(cache_key)
if cached_data && !option_chain_stale?(expiry)
  return cached_data
end
```

**DON'T:**
```ruby
cached_data = Rails.cache.read(cache_key)
return cached_data if cached_data
```

---

## Architecture Rules

### Domain Organization

#### RULE: Always respect domain boundaries - no cross-domain dependencies
**DO:**
```
app/services/
  signal/
    engine.rb  # Only depends on signal domain
  options/
    chain_analyzer.rb  # Only depends on options domain
```

**DON'T:**
```ruby
# signal/engine.rb
module Signal
  class Engine
    def analyze
      # Directly calling options service - violates domain boundary
      Options::ChainAnalyzer.call(...)
    end
  end
end
```

#### RULE: Always extract shared logic to concerns or base classes
**DO:**
```ruby
# app/models/concerns/instrument_helpers.rb
module InstrumentHelpers
  extend ActiveSupport::Concern
  # shared logic
end

# app/models/instrument.rb
class Instrument < ApplicationRecord
  include InstrumentHelpers
end
```

**DON'T:**
```ruby
# Duplicating logic across models
class Instrument < ApplicationRecord
  def ltp
    # logic
  end
end

class Derivative < ApplicationRecord
  def ltp
    # same logic duplicated
  end
end
```

### Service Patterns

#### RULE: Never put business logic in controllers or models - always use services
**DO:**
```ruby
# app/services/signal/engine.rb
module Signal
  class Engine
    def self.run_for(index_cfg)
      # business logic here
    end
  end
end

# app/controllers/api/signals_controller.rb
def create
  result = Signal::Engine.run_for(index_cfg)
  render json: { result: result }
end
```

**DON'T:**
```ruby
# app/controllers/api/signals_controller.rb
def create
  instrument = Instrument.find_by(symbol_name: index_cfg[:key])
  candles = instrument.candle_series(interval: '5')
  # ... 50 lines of business logic ...
  render json: { result: analysis }
end
```

#### RULE: Always use PORO (Plain Old Ruby Objects) for services
**DO:**
```ruby
module Signal
  class Engine
    def self.run_for(index_cfg)
      # pure Ruby logic
    end
  end
end
```

**DON'T:**
```ruby
# Services inheriting from ActiveRecord or other framework classes
class Engine < ActiveRecord::Base
end
```

### Configuration

#### RULE: Always load configuration via AlgoConfig.fetch
**DO:**
```ruby
config = AlgoConfig.fetch
signals_cfg = config[:signals] || {}
```

**DON'T:**
```ruby
config = YAML.load_file('config/algo.yml')
signals_cfg = config['signals'] || {}
```

#### RULE: Always store secrets in encrypted credentials or environment variables
**DO:**
```ruby
client_id = Rails.application.credentials.dhanhq[:client_id]
# or
client_id = ENV['DHANHQ_CLIENT_ID']
```

**DON'T:**
```ruby
client_id = 'hardcoded_client_id_12345'
```

### Real-time Services

#### RULE: Always use Singleton pattern for real-time services (WebSocket, market feeds)
**DO:**
```ruby
module Live
  class MarketFeedHub
    include Singleton

    def running?
      @running ||= false
    end
  end
end
```

**DON'T:**
```ruby
class MarketFeedHub
  def self.new
    @instance ||= super
  end
end
```

#### RULE: Always use descriptive thread names
**DO:**
```ruby
@thread = Thread.new { run_loop }
@thread.name = 'signal-scheduler'
@thread.name = 'pnl-updater-service'
```

**DON'T:**
```ruby
@thread = Thread.new { run_loop }
# No thread name set
```

#### RULE: Always ensure thread safety with mutexes when needed
**DO:**
```ruby
def initialize
  @queue = {}
  @mutex = Monitor.new
end

def add_item(item)
  @mutex.synchronize do
    @queue[item.id] = item
  end
end
```

**DON'T:**
```ruby
def initialize
  @queue = {}
end

def add_item(item)
  @queue[item.id] = item  # Not thread-safe
end
```

---

## Naming Conventions

### Files

#### RULE: Always use snake_case for file names
**DO:**
```
entry_guard.rb
risk_manager_service.rb
position_tracker.rb
```

**DON'T:**
```
EntryGuard.rb
RiskManagerService.rb
PositionTracker.rb
```

#### RULE: Always name service files as service_name.rb in app/services/domain/
**DO:**
```
app/services/signal/engine.rb
app/services/options/chain_analyzer.rb
```

**DON'T:**
```
app/services/signal_engine.rb
app/services/optionsChainAnalyzer.rb
```

#### RULE: Always name test files as *_spec.rb
**DO:**
```
spec/models/instrument_spec.rb
spec/services/signal/engine_spec.rb
```

**DON'T:**
```
spec/models/instrument_test.rb
spec/services/signal/engine.rb
```

### Classes and Modules

#### RULE: Always use CamelCase for class and module names
**DO:**
```ruby
class SignalEngine
module Options
  class ChainAnalyzer
  end
end
```

**DON'T:**
```ruby
class signal_engine
module options
  class chain_analyzer
  end
end
```

#### RULE: Always use :: separator for namespaced classes
**DO:**
```ruby
Signal::Engine
Options::ChainAnalyzer
Live::MarketFeedHub
```

**DON'T:**
```ruby
Signal.Engine
Options.ChainAnalyzer
Live_MarketFeedHub
```

### Methods

#### RULE: Always use snake_case for method names
**DO:**
```ruby
def calculate_pnl
def fetch_option_chain
def update_position
```

**DON'T:**
```ruby
def calculatePnl
def fetchOptionChain
def UpdatePosition
```

#### RULE: Always end predicate methods with ?
**DO:**
```ruby
def running?
def active?
def stale?
```

**DON'T:**
```ruby
def running
def is_active
def is_stale
```

#### RULE: Always end destructive methods with !
**DO:**
```ruby
def save!
def update!
def destroy!
```

**DON'T:**
```ruby
def save_force
def update_force
def destroy_force
```

### Constants

#### RULE: Always use SCREAMING_SNAKE_CASE for constants
**DO:**
```ruby
RETRY_COUNT = 3
DEFAULT_THRESHOLDS = { funds: 60.seconds }.freeze
FLUSH_INTERVAL_SECONDS = 0.25
```

**DON'T:**
```ruby
RetryCount = 3
default_thresholds = { funds: 60.seconds }
flushIntervalSeconds = 0.25
```

#### RULE: Always extract magic numbers to named constants
**DO:**
```ruby
MAX_RETRIES = 3
TIMEOUT_SECONDS = 30

def retry_operation
  MAX_RETRIES.times do
    # ...
  end
end
```

**DON'T:**
```ruby
def retry_operation
  3.times do  # Magic number
    # ...
  end
end
```

### Database

#### RULE: Always use plural table names
**DO:**
```ruby
create_table :instruments
create_table :position_trackers
create_table :trading_signals
```

**DON'T:**
```ruby
create_table :instrument
create_table :position_tracker
create_table :trading_signal
```

#### RULE: Always use snake_case for column names
**DO:**
```ruby
t.string :symbol_name
t.decimal :strike_price
t.integer :lot_size
```

**DON'T:**
```ruby
t.string :symbolName
t.decimal :strikePrice
t.integer :lotSize
```

#### RULE: Always end foreign key columns with _id
**DO:**
```ruby
t.bigint :instrument_id
t.bigint :paper_order_id
```

**DON'T:**
```ruby
t.bigint :instrument
t.bigint :orderId
```

#### RULE: Always end polymorphic type columns with _type
**DO:**
```ruby
t.string :watchable_type
t.bigint :watchable_id
```

**DON'T:**
```ruby
t.string :entity_type
t.bigint :entity_id
```

---

## Git Workflow Rules

### Commit Messages

#### RULE: Always use imperative mood in commit messages
**DO:**
```
Add throttle guard to quotes API
Fix WebSocket connection handling
Update RuboCop configuration
```

**DON'T:**
```
Added throttle guard to quotes API
Fixed WebSocket connection handling
Updates RuboCop configuration
```

#### RULE: Never exceed 72 characters in commit message first line
**DO:**
```
Add throttle guard to quotes API
```

**DON'T:**
```
Add throttle guard to quotes API to prevent rate limiting issues when multiple clients connect simultaneously
```

#### RULE: Never use CamelCase in commit messages
**DO:**
```
Add signal generation engine
Fix position tracker sync
```

**DON'T:**
```
AddSignalGenerationEngine
FixPositionTrackerSync
```

### Pull Requests

#### RULE: Always include verification steps in PR description
**DO:**
```
## Verification
- [x] `bin/rubocop` - Code style compliance
- [x] `bin/brakeman` - Security scan
- [x] `bin/rails test` - Test suite
```

**DON'T:**
```
## Verification
- Tests pass
```

#### RULE: Always include request/response samples for API changes
**DO:**
```
## API Changes
### Request
GET /api/health

### Response
{
  "mode": "paper",
  "watchlist": 3,
  "active_positions": 2
}
```

**DON'T:**
```
## API Changes
Updated health endpoint
```

---

## Documentation Rules

### Code Documentation

#### RULE: Always document complex logic with comments
**DO:**
```ruby
# Calculate position size based on risk percentage and account balance
# Uses Kelly Criterion with safety factor to prevent over-leveraging
def calculate_position_size(risk_pct:, account_balance:)
  # implementation
end
```

**DON'T:**
```ruby
def calculate_position_size(risk_pct:, account_balance:)
  # Complex formula without explanation
  (account_balance * risk_pct * 0.25) / (entry_price * lot_size)
end
```

#### RULE: Always use TODO: format for TODO comments
**DO:**
```ruby
# TODO: Integrate with actual IV rank calculation
# TODO: Add retry logic for external API calls
```

**DON'T:**
```ruby
# TODO integrate with IV rank
# FIXME add retry logic
```

#### RULE: Always use NOTE: format for NOTE comments
**DO:**
```ruby
# NOTE: Order updates use PositionSyncService polling (not WebSocket)
# NOTE: Connection state updated when first tick received
```

**DON'T:**
```ruby
# Note: Order updates use polling
# Important: Connection state updated
```

### Markdown Documentation

#### RULE: Always use Title Case for level-one and level-two headings
**DO:**
```markdown
# Project Overview
## Setup Instructions
### Configuration Options
```

**DON'T:**
```markdown
# project overview
## setup instructions
### configuration options
```

#### RULE: Always document environment variables in tables
**DO:**
```markdown
| Variable | Purpose | Default |
|----------|---------|---------|
| `DHANHQ_CLIENT_ID` | DhanHQ API client ID | Required |
| `DHANHQ_ACCESS_TOKEN` | DhanHQ API access token | Required |
```

**DON'T:**
```markdown
DHANHQ_CLIENT_ID - DhanHQ API client ID
DHANHQ_ACCESS_TOKEN - DhanHQ API access token
```

#### RULE: Always use blockquotes starting with > **Warning:** for critical warnings
**DO:**
```markdown
> **Warning:** This system involves real money trading - use appropriate risk management
```

**DON'T:**
```markdown
WARNING: This system involves real money trading
```

---

## Security Rules

### Secrets Management

#### RULE: Never commit config/master.key to version control
**DO:**
```gitignore
# .gitignore
config/master.key
```

**DON'T:**
```bash
git add config/master.key
git commit -m "Add master key"
```

#### RULE: Always load API keys from environment variables
**DO:**
```ruby
client_id = ENV['DHANHQ_CLIENT_ID']
access_token = ENV['DHANHQ_ACCESS_TOKEN']
```

**DON'T:**
```ruby
client_id = 'hardcoded_client_id_12345'
access_token = 'hardcoded_token_abcdef'
```

#### RULE: Always filter sensitive parameters from logs
**DO:**
```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt
]
```

**DON'T:**
```ruby
# Logging sensitive data
Rails.logger.info("API call with token: #{access_token}")
```

---

## Enforcement

These rules are enforced via:
- **RuboCop**: Automated code style checking (`.rubocop.yml`)
- **Brakeman**: Security vulnerability scanning
- **RSpec**: Test coverage and quality
- **Code Review**: Manual review process
- **CI/CD**: Automated checks in pipeline

---

*Last Updated: 2025-01-XX*
*Repository: algo_scalper_api*
