# Test Throttling Configuration

This document explains how to configure test execution to prevent API rate limits.

## Problem

When running the full test suite, multiple tests may make API calls simultaneously, causing rate limit errors (429 Too Many Requests). This is especially problematic when:
- Regenerating VCR cassettes
- Running tests that don't have cassettes yet
- Running integration tests that make real API calls

## Solution

The test suite is configured to run tests **sequentially** by default to prevent rate limits. Additional throttling options are available via environment variables.

## Configuration Options

### 1. Sequential Execution (Default)

RSpec runs tests sequentially by default (one at a time). This prevents parallel API calls that could trigger rate limits.

**Note:** If you're using the `parallel_tests` gem, you can disable it for API tests by running tests normally without the `parallel_rspec` command.

### 2. VCR Recording Delay

When VCR is recording new cassettes, a delay is added between tests to prevent rapid API calls.

**Default delay:** 0.5 seconds

**To customize:**
```bash
VCR_DELAY_BETWEEN_TESTS=1.0 bundle exec rspec
```

### 3. Global Test Delay

Add a delay between ALL tests (not just VCR tests).

**Usage:**
```bash
TEST_DELAY=0.1 bundle exec rspec
```

This adds a 100ms delay between every test.

### 4. VCR Mode

Control how VCR handles cassettes:

- `:once` (default): Use cassette if exists, record if missing
- `:all`: Record all interactions (overwrites existing cassettes)
- `:none`: Disable recording (fails if cassette missing)

**Usage:**
```bash
VCR_MODE=all bundle exec rspec  # Record all interactions
VCR_MODE=none bundle exec rspec # Fail if cassette missing
```

### 5. VCR Recording Delay

Add delay specifically when recording new cassettes:

**Usage:**
```bash
VCR_RECORDING_DELAY=0.5 bundle exec rspec
```

## Recommended Workflows

### Running Full Test Suite

```bash
# Default: Sequential execution with VCR delays
bundle exec rspec

# With explicit delays for safety
TEST_DELAY=0.1 VCR_DELAY_BETWEEN_TESTS=0.5 bundle exec rspec
```

### Regenerating VCR Cassettes

```bash
# Record all interactions with delays
VCR_MODE=all VCR_DELAY_BETWEEN_TESTS=1.0 bundle exec rspec spec/integration/order_placement_spec.rb
```

### Running Individual Tests

```bash
# Run one test at a time (safest)
bundle exec rspec spec/integration/order_placement_spec.rb:272

# Run a few tests with delay
TEST_DELAY=0.2 bundle exec rspec spec/integration/order_placement_spec.rb:272 spec/integration/order_placement_spec.rb:289
```

### Running Tests in Small Batches

```bash
# Run 2-3 tests at a time with delay
TEST_DELAY=0.2 bundle exec rspec spec/integration/order_placement_spec.rb --format progress --fail-fast
```

## Best Practices

1. **Always run tests sequentially** when they involve API calls
2. **Use VCR cassettes** to avoid real API calls in most cases
3. **Add delays when regenerating cassettes** to prevent rate limits
4. **Run tests one or two at a time** when debugging or regenerating cassettes
5. **Use `--fail-fast`** to stop on first failure and avoid unnecessary API calls

## Example: Regenerating a Single Cassette

```bash
# Delete the old cassette
rm spec/cassettes/Order_Placement_Integration/Entry_Guard_Integration/when_attempting_entry/calculates_correct_quantity_using_capital_allocator.yml

# Run the specific test with recording enabled and delays
VCR_MODE=all VCR_DELAY_BETWEEN_TESTS=1.0 bundle exec rspec spec/integration/order_placement_spec.rb:272
```

## Troubleshooting

### Still Getting Rate Limit Errors?

1. Increase delays:
   ```bash
   VCR_DELAY_BETWEEN_TESTS=2.0 TEST_DELAY=0.5 bundle exec rspec
   ```

2. Run tests one at a time:
   ```bash
   bundle exec rspec spec/integration/order_placement_spec.rb:272
   bundle exec rspec spec/integration/order_placement_spec.rb:289
   ```

3. Check if VCR cassettes exist:
   ```bash
   ls -la spec/cassettes/**/*.yml
   ```

4. Ensure VCR is enabled:
   ```bash
   # VCR should be enabled by default via :vcr metadata
   # Check that tests have :vcr tag
   ```

