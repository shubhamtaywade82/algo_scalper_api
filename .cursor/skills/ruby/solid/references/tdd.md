# Test-Driven Development

All code examples in this document are Ruby (RSpec).

## The Core Loop

```
RED → GREEN → REFACTOR → RED → ...
```

### RED Phase
Write a failing test that describes the behavior you want. The test should:
- Use domain language, not technical jargon
- Describe WHAT, not HOW
- Be a concrete example, not an abstract statement

```ruby
# BAD: Abstract
it 'can add numbers' do
end

# GOOD: Concrete example
it 'returns 5 when adding 2 and 3' do
  expect(Calculator.new.add(2, 3)).to eq(5)
end
```

### GREEN Phase
Write the **simplest possible code** to make the test pass. Two strategies:

1. **Fake It** - Return a hardcoded value
   ```ruby
   def add(a, b)
     5  # Simplest thing!
   end
   ```

2. **Obvious Implementation** - If you know the solution
   ```ruby
   def add(a, b)
     a + b
   end
   ```

**Prefer Fake It** when learning or unsure. Let more tests drive the real implementation.

### REFACTOR Phase
This is where **design happens**. Look for:
- Duplication (but wait for Rule of Three)
- Long methods to extract
- Poor names to improve
- Complex conditions to simplify

## The Three Laws of TDD

1. **No production code** without a failing test
2. **No more test code** than sufficient to fail
3. **No more production code** than sufficient to pass the one failing test

## The Rule of Three

**Only extract duplication when you see it THREE times.**

Wrong abstractions are worse than duplication. Wait for the pattern to emerge.

## Arrange-Act-Assert (RSpec)

Structure every example:

```ruby
it 'calculates total with discount' do
  # ARRANGE - Set up the world
  order = Order.new
  order.add_item(price: 100)
  discount = PercentDiscount.new(10)

  # ACT - Execute the behavior
  total = order.calculate_total(discount)

  # ASSERT - Verify the outcome
  expect(total).to eq(90)
end
```

## Writing Tests Backwards

Sometimes write AAA in reverse:
1. Write the ASSERT first - what do you want to verify?
2. Write the ACT - what action produces that result?
3. Write the ARRANGE - what setup is needed?

## Test Naming (RSpec)

- Use **behavior-driven names** with domain language
- **One example per test** for easy debugging
- Avoid leaking implementation details

```ruby
# BAD: Technical
it 'sets the data property to 1'

# GOOD: Behavior-focused
it 'recognizes "mom" as a palindrome'
```

## Common Mistakes

1. **Writing code before tests** - Violates the fundamental principle
2. **Writing too much test** - Just enough to fail
3. **Writing too much code** - Just enough to pass
4. **Skipping refactor** - This is where design lives
5. **Testing implementation** - Test behavior, not how it's done
6. **Abstract test names** - Use concrete examples
7. **Extracting too early** - Wait for Rule of Three
