# Managing Complexity

All code examples in this document are Ruby.

## Essential vs Accidental Complexity

- **Essential** — Inherent to the problem (business rules, domain). Cannot be removed, only managed.
- **Accidental** — Introduced by our solutions (poor abstractions, unnecessary indirection). Minimize it.

## Detecting Complexity

- **Change amplification** — Small change requires touching many files.
- **Cognitive load** — Hard to understand; need to hold too much in memory.
- **Unknown unknowns** — Surprising behavior; hidden side effects.

## Fighting Complexity

- **YAGNI** — Don't build what you don't need now.
- **KISS** — Simplest solution that works.
- **DRY + Rule of Three** — Extract duplication only after the third occurrence.

```ruby
# Over-engineered
class UserServiceFactoryProvider
  def self.instance
    @instance ||= new
  end
  def create_factory
    UserServiceFactory.new
  end
end

# KISS
class UserService
  def find_user(id)
    # ...
  end
end
```

## The Four Elements of Simple Design (XP)

1. **Runs all the tests**
2. **Expresses intent**
3. **No duplication** (Rule of Three)
4. **Minimal** — Fewest classes and methods

## Boy Scout Rule

> "Leave the code better than you found it."

Every touch: improve one small thing (name, extract method, add test).
