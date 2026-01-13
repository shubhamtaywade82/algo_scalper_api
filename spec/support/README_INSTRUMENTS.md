# Test Environment Instruments Import

This helper allows you to import real Instruments and Derivatives data into the test environment, ensuring tests use correct security IDs and instrument data instead of factory-generated values.

## Quick Start

### 1. Create Filtered CSV (Recommended for Faster Tests)

Create a filtered CSV with only NIFTY, BANKNIFTY, SENSEX indexes and their derivatives:

```bash
RAILS_ENV=test bin/rails test:instruments:filter_csv
```

This creates `tmp/dhan_scrip_master_filtered.csv` with:
- 3 index instruments (NIFTY-13, BANKNIFTY-25, SENSEX-51)
- ~9,600 derivatives (options and futures)
- Much faster import (~96k rows vs 217k+ rows)

### 2. Import Instruments for Tests

```bash
# Import from filtered CSV (faster, recommended)
FILTERED_CSV=true RAILS_ENV=test bin/rails test:instruments:import

# Or import from full CSV
RAILS_ENV=test bin/rails test:instruments:import

# Check status
RAILS_ENV=test bin/rails test:instruments:status
```

### 3. Auto-Import Before Test Suite (After Truncation)

The database cleaner automatically imports instruments and derivatives after truncation but before tests run. Enable it with:

```bash
# Option 1: Use filtered CSV (faster, recommended)
FILTERED_CSV=true IMPORT_INSTRUMENTS_FOR_TESTS=true bundle exec rspec

# Option 2: Use full CSV
IMPORT_INSTRUMENTS_FOR_TESTS=true bundle exec rspec

# Option 3: Use AUTO_IMPORT_INSTRUMENTS (database cleaner specific)
FILTERED_CSV=true AUTO_IMPORT_INSTRUMENTS=true bundle exec rspec
```

**Note:** The import happens **after** `DatabaseCleaner.clean_with(:truncation)` but **before** tests run, ensuring:
- Clean database state (truncated)
- Real instruments populated (NIFTY-13, BANKNIFTY-25, SENSEX-51, etc.)
- All derivatives available for tests
- Tests use real security IDs and instrument data

## How It Works

1. **CSV Source**: Uses the cached CSV at `tmp/dhan_scrip_master.csv` (same as development/production)
2. **Import Process**: Uses `InstrumentsImporter.import_from_csv` to upsert instruments and derivatives
3. **Idempotent**: Safe to run multiple times - uses upsert logic, won't duplicate data
4. **Optional**: Tests can still run without imported data (uses factories as fallback)

## Benefits

- ✅ **Real Security IDs**: Tests use actual DhanHQ security IDs (e.g., NIFTY index: `13`, BANKNIFTY index: `25`)
- ✅ **Real Instrument Data**: Tests use actual lot sizes, tick sizes, and other instrument properties
- ✅ **Better Integration Tests**: Tests that rely on instrument lookups work with real data
- ✅ **Consistent with Production**: Test data matches production/development data

## Usage in Tests

### Option 1: Use Real Instruments (Recommended)

```ruby
# In your test
let(:nifty_index) { InstrumentsHelper.find_real_instrument(symbol_name: 'NIFTY') }
let(:nifty_future) { InstrumentsHelper.find_real_derivative(symbol_name: 'NIFTY', instrument_type: 'FUTURE') }

# Or use Instrument/Derivative queries directly
let(:nifty) { Instrument.segment_index.find_by(symbol_name: 'NIFTY') }
```

### Option 2: Use Factories (Fallback)

```ruby
# Factories still work if real data isn't available
let(:instrument) { create(:instrument, :nifty_index) }
```

## Rake Tasks

### `test:instruments:filter_csv`
Creates a filtered CSV with only NIFTY, BANKNIFTY, SENSEX indexes and their derivatives.

```bash
RAILS_ENV=test bin/rails test:instruments:filter_csv
```

**Output:** `tmp/dhan_scrip_master_filtered.csv`
- Contains ~9,600 rows (vs 217k+ in full CSV)
- Includes 3 index instruments and all their derivatives
- Much faster to import and process

### `test:instruments:import`
Imports instruments and derivatives for test environment.

```bash
# Use filtered CSV (faster)
FILTERED_CSV=true RAILS_ENV=test bin/rails test:instruments:import

# Use full CSV
RAILS_ENV=test bin/rails test:instruments:import
```

### `test:instruments:status`
Checks if instruments are imported and shows status.

```bash
RAILS_ENV=test bin/rails test:instruments:status
```

## CSV Files

### Full CSV (`tmp/dhan_scrip_master.csv`)
- Created automatically when running `bin/rails instruments:import` in development
- Shared between development and test environments
- Cached for 24 hours (see `InstrumentsImporter::CACHE_MAX_AGE`)
- Contains all instruments and derivatives (~217k rows, ~35MB)

### Filtered CSV (`tmp/dhan_scrip_master_filtered.csv`)
- Created by running `RAILS_ENV=test bin/rails test:instruments:filter_csv`
- Contains only NIFTY, BANKNIFTY, SENSEX indexes and their derivatives
- ~9,600 rows (~1.6MB) - much faster to import
- Use with `FILTERED_CSV=true` environment variable
- **Note:** This file is gitignored (generated file)

**Note:** If the CSV doesn't exist, the import will download it from DhanHQ.

## Notes

- **Database Cleanup**: Test database is cleaned between runs, so you may need to re-import if using `DatabaseCleaner`
- **Performance**: Import takes a few seconds, but only needs to run once per test session
- **Transaction Safety**: Import happens before test suite, outside of transactions

