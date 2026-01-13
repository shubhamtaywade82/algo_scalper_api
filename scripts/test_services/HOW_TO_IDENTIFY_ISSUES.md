# How to Identify Service Issues

This guide explains how to identify which services are having issues or not working as expected.

## Quick Methods

### Method 1: Run All Tests with Summary (Recommended)

```bash
./scripts/test_services/run_all_tests.sh
```

**Output shows:**
- ✅ Passed: X
- ⚠️  Warnings: X
- ❌ Failed: X
- List of failed tests

**Example:**
```
==========================================
  Test Summary
==========================================
✅ Passed: 4
⚠️  Warnings: 1
❌ Failed: 1

Failed tests:
  ❌ test_capital_allocator.rb
```

### Method 2: Generate Detailed Summary Report

```bash
ruby scripts/test_services/test_summary.rb
```

**This will:**
- Run all tests automatically
- Categorize each test (Passed/Warnings/Failed)
- Show error messages for failed tests
- Exit with code 1 if any tests failed (useful for CI/CD)

**Example output:**
```
✅ Passing Services
  - redis_tick_cache
  - redis_pnl_cache
  - position_index

⚠️  Services with Warnings
  - active_cache

❌ Failing Services
  - capital_allocator
    Error: undefined method 'current_capital'
```

### Method 3: Check Individual Test Output

Run a specific test and look for indicators:

```bash
ruby scripts/test_services/test_<service_name>.rb
```

**Look for:**
- ✅ **Green checkmark** = Service is working
- ❌ **Red X** = Service has errors
- ⚠️  **Yellow warning** = Service works but has warnings
- ℹ️  **Blue info** = Informational message

## Understanding Test Output

### Success Indicators
```
✅ Service started
✅ Test passed
✅ Data retrieved correctly
```

### Error Indicators
```
❌ undefined method 'method_name'
❌ ArgumentError - missing keyword: :param
❌ NoMethodError
❌ LoadError
```

### Warning Indicators
```
⚠️  No active positions found
⚠️  Service may not be fully configured
⚠️  Quantity is 0 (may be due to validation)
```

## Common Issues and Solutions

### Issue: `undefined method 'method_name'`

**Meaning:** Test is calling a method that doesn't exist in the service.

**Solution:**
1. Check the actual service implementation
2. Verify if it's a class method vs instance method
3. Check method name spelling
4. Update test script to match actual API

**Example:**
```ruby
# Wrong (instance method)
allocator = Capital::Allocator.new
allocator.current_capital  # ❌ undefined method

# Correct (class method)
Capital::Allocator.available_cash  # ✅ works
```

### Issue: `ArgumentError - missing keyword: :param`

**Meaning:** Test is passing wrong parameters to a method.

**Solution:**
1. Check the service method signature
2. Verify parameter names match
3. Check if parameters are required or optional
4. Update test script with correct parameters

**Example:**
```ruby
# Wrong
strike_selector.select(index: :NIFTY)  # ❌ missing keyword: :index_key

# Correct
strike_selector.select(index_key: :NIFTY)  # ✅ works
```

### Issue: `NoMethodError` for scopes

**Meaning:** Model doesn't have the scope defined.

**Solution:**
1. Check if scope exists in model
2. Use correct scope name
3. Or use `.where(...)` instead

**Example:**
```ruby
# Wrong
Derivative.active  # ❌ undefined method 'active'

# Correct
Derivative.where(...)  # ✅ works
```

### Issue: Service shows warnings but passes

**Meaning:** Service is working but has limitations or missing data.

**Examples:**
- No active positions (expected if no trades)
- No watchlist items (expected if not configured)
- Quantity is 0 (may be due to validation rules)

**Action:** Usually safe to ignore, but check if data should exist.

## Exit Codes

- **Exit 0** = All tests passed
- **Exit 1** = One or more tests failed

Useful for CI/CD:
```bash
if ./scripts/test_services/run_all_tests.sh; then
  echo "All services working"
else
  echo "Some services have issues"
  exit 1
fi
```

## Service Status Checklist

After running tests, check:

- [ ] All quick tests pass (✅)
- [ ] No critical errors (❌)
- [ ] Warnings are acceptable (⚠️)
- [ ] Long-running tests can be run when services are active
- [ ] Integration test passes when all services are running

## Next Steps After Identifying Issues

1. **Read the error message** - It tells you exactly what's wrong
2. **Check the service implementation** - Verify the actual API
3. **Update the test script** - Fix the test to match the service
4. **Re-run the test** - Verify the fix works
5. **If service itself has issues** - Fix the service, not just the test

## Quick Reference

| Indicator | Meaning | Action |
|-----------|---------|--------|
| ✅ | Success | None - service is working |
| ⚠️  | Warning | Review - usually safe to ignore |
| ❌ | Error | Fix - service has issues |
| ℹ️  | Info | None - informational only |

## Examples

### Example 1: All Services Working
```
✅ Passed: 6
⚠️  Warnings: 0
❌ Failed: 0
```
→ **All services are working correctly!**

### Example 2: Some Services Have Issues
```
✅ Passed: 4
⚠️  Warnings: 1
❌ Failed: 1

Failed tests:
  ❌ test_capital_allocator.rb
```
→ **One service needs attention. Run the individual test for details.**

### Example 3: Multiple Issues
```
✅ Passed: 2
⚠️  Warnings: 2
❌ Failed: 2

Failed tests:
  ❌ test_capital_allocator.rb
  ❌ test_options_services.rb
```
→ **Multiple services need attention. Check each one individually.**

