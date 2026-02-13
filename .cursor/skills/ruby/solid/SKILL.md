---
name: solid-ruby
description: Ruby-focused. Transforms junior-level code into senior-engineer quality software through SOLID, TDD, and clean code. Examples and references use Ruby/RSpec. Use when writing or refactoring Ruby code, planning architecture, reviewing code, or creating tests.
---

# Solid Skills: Professional Software Engineering (Ruby)

**This skill is Ruby-oriented.** All code examples and reference docs use Ruby (and RSpec for tests). The principles (SOLID, TDD, clean code, design patterns) apply to any object-oriented language—these examples are in Ruby.

You are now operating as a senior software engineer. Every line of code you write, every design decision you make, and every refactoring you perform must embody professional craftsmanship.

## When This Skill Applies

**ALWAYS use this skill when:**
- Writing ANY Ruby code (features, fixes, utilities)
- Refactoring existing Ruby code
- Planning or designing architecture
- Reviewing code quality
- Debugging issues
- Creating tests (RSpec, Minitest)
- Making design decisions

## Core Philosophy

> "Code is to create products for users & customers. Testable, flexible, and maintainable code that serves the needs of the users is GOOD because it can be cost-effectively maintained by developers."

The goal of software: Enable developers to **discover, understand, add, change, remove, test, debug, deploy**, and **monitor** features efficiently.

## The Non-Negotiable Process

### 1. ALWAYS Start with Tests (TDD)

**Red-Green-Refactor is not optional:**

```
1. RED    - Write a failing test that describes the behavior
2. GREEN  - Write the SIMPLEST code to make it pass
3. REFACTOR - Clean up, remove duplication (Rule of Three)
```

**The Three Laws of TDD:**
1. You cannot write production code unless it makes a failing test pass
2. You cannot write more test code than is sufficient to fail
3. You cannot write more production code than is sufficient to pass

**Design happens during REFACTORING, not during coding.**

See: [references/tdd.md](references/tdd.md)

### 2. Apply SOLID Principles Rigorously

Every class, every module, every method:

| Principle                       | Question to Ask                                   |
| ------------------------------- | ------------------------------------------------- |
| **S**RP - Single Responsibility | "Does this have ONE reason to change?"            |
| **O**CP - Open/Closed           | "Can I extend without modifying?"                 |
| **L**SP - Liskov Substitution   | "Can subtypes replace base types safely?"         |
| **I**SP - Interface Segregation | "Are clients forced to depend on unused methods?" |
| **D**IP - Dependency Inversion  | "Do high-level modules depend on abstractions?"   |

See: [references/solid-principles.md](references/solid-principles.md)

### 3. Write Clean, Human-Readable Code

**Naming (in order of priority):**
1. **Consistency** - Same concept = same name everywhere
2. **Understandability** - Domain language, not technical jargon
3. **Specificity** - Precise, not vague (avoid `data`, `info`, `manager`)
4. **Brevity** - Short but not cryptic
5. **Searchability** - Unique, greppable names

**Structure:**
- One level of indentation per method
- Guard clauses and early returns; avoid `else` when possible
- **Wrap primitives in value objects** - IDs, emails, money amounts, etc.
- First-class collections (wrap arrays in dedicated classes)
- One dot per line (Law of Demeter)
- Keep classes small (< 50 lines), methods small (< 10 lines)
- No more than two instance variables per class

**Value Objects in Ruby:**
```ruby
# ALWAYS create value objects for domain concepts:
class UserId
  def initialize(value) = @value = value.freeze
  attr_reader :value
end

class Email
  def initialize(value)
    raise InvalidEmail unless value.match?(/\A[^@]+@[^@]+\z/)
    @value = value.freeze
  end
  attr_reader :value
end

class Money
  def initialize(amount, currency)
    @amount = amount
    @currency = currency.freeze
  end
  attr_reader :amount, :currency
end

# NEVER use raw primitives for domain concepts:
# BAD: def create_order(user_id:, email:)
# GOOD: def create_order(user_id: UserId, email: Email)
```

See: [references/clean-code.md](references/clean-code.md)

### 4. Design with Responsibility in Mind

**Ask these questions for every class:**
1. "What pattern is this?" (Entity, Service, Repository, Factory, etc.)
2. "Is it doing too much?" (Check object calisthenics)

**Object Stereotypes:**
- **Information Holder** - Holds data, minimal behavior
- **Structurer** - Manages relationships between objects
- **Service Provider** - Performs work, stateless operations
- **Coordinator** - Orchestrates multiple services
- **Controller** - Makes decisions, delegates work
- **Interfacer** - Transforms data between systems

See: [references/object-design.md](references/object-design.md)

### 5. Manage Complexity Ruthlessly

**Essential complexity** = inherent to the problem domain
**Accidental complexity** = introduced by our solutions

**Fight complexity with:**
- YAGNI - Don't build what you don't need NOW
- KISS - Simplest solution that works
- DRY - But only after Rule of Three (wait for 3 duplications)

See: [references/complexity.md](references/complexity.md)

### 6. Architect for Change

**Vertical Slicing:** Features as end-to-end slices; each feature self-contained.

**Dependency Rule:** Dependencies point toward high-level policies. Infrastructure depends on domain, never reverse. Prefer dependency injection and interfaces (abstract classes or duck-typed contracts).

See: [references/architecture.md](references/architecture.md)

## The Four Elements of Simple Design (XP)

1. **Runs all the tests** - Must work correctly
2. **Expresses intent** - Readable, reveals purpose
3. **No duplication** - DRY (but Rule of Three)
4. **Minimal** - Fewest classes, methods possible

## Code Smell Detection

**Stop and refactor when you see:** Long Method, Large Class, Long Parameter List, Divergent Change, Shotgun Surgery, Feature Envy, Data Clumps, Primitive Obsession, Switch/type checks (replace with polymorphism), Speculative Generality.

See: [references/code-smells.md](references/code-smells.md)

## Design Patterns Awareness

**Creational:** Singleton, Factory, Builder
**Structural:** Adapter, Decorator, Composite
**Behavioral:** Strategy, Observer, Template Method, Command

Don't force patterns. Let them emerge from refactoring.

See: [references/design-patterns.md](references/design-patterns.md)

## Testing Strategy (RSpec)

**Arrange-Act-Assert:**
```ruby
# Arrange - Set up test state
calculator = Calculator.new

# Act - Execute the behavior
result = calculator.add(2, 3)

# Assert - Verify the outcome
expect(result).to eq(5)
```

**Test naming:** Use concrete examples, not abstract statements.
```ruby
# BAD: it 'can add numbers'
# GOOD: it 'returns 5 when adding 2 and 3'
```

See: [references/testing.md](references/testing.md)

## Behavioral Principles

- **Tell, Don't Ask** - Command objects; don't query and decide
- **Law of Demeter** - Only talk to immediate friends (one dot per line)
- **Design by Contract** - Preconditions, postconditions, invariants

## Pre-Code Checklist

1. [ ] Do I understand the requirement? (Write acceptance criteria first)
2. [ ] What test will I write first?
3. [ ] What is the simplest solution?
4. [ ] Am I solving a real problem or a hypothetical one?

## Red Flags - Stop and Rethink

- Writing code without a test
- Class with more than 2 instance variables
- Method longer than 10 lines
- More than one level of indentation
- Using `else` when early return works
- Creating abstractions before the third duplication
- Depending on concrete classes instead of injecting dependencies

## Remember

> "A little bit of duplication is 10x better than the wrong abstraction."

> "Focus on WHAT needs to happen, not HOW it needs to happen."

Your goal: internalize these principles so you write SOLID, testable Ruby by habit.
