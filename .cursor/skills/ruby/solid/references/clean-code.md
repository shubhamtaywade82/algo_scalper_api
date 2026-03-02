# Clean Code Practices

All code examples in this document are Ruby.

## What is Clean Code?

Code that is:
- **Easy to understand** - reveals intent clearly
- **Easy to change** - modifications are localized
- **Easy to test** - dependencies are injectable
- **Simple** - no unnecessary complexity

## Naming Principles

### 1. Consistency & Uniqueness (HIGHEST PRIORITY)
Same concept = same name everywhere.

```ruby
# BAD: Inconsistent names for same concept
get_user_by_id(id)
fetch_customer_by_id(id)

# GOOD: Consistent
find_user(id)
find_order(id)
```

### 2. Understandability
Use domain language, not technical jargon.

```ruby
# BAD: Technical
arr = users.select(&:active?)

# GOOD: Domain language
active_customers = users.select(&:active?)
```

### 3. Specificity
Avoid vague names: `data`, `info`, `manager`, `handler`, `processor`, `utils`

```ruby
# BAD: Vague
class DataManager
def process_info(data)

# GOOD: Specific
class OrderRepository
def validate_payment(payment)
```

### 4. Brevity (but not at cost of clarity)
Short names are good only if meaning is preserved.

```ruby
# BAD: Too cryptic
usr_lst = get_usrs

# GOOD: Brief but clear
active_users = fetch_active_users
```

---

## Object Calisthenics (adapted for Ruby)

### 1. One Level of Indentation per Method
Extract methods to avoid nested blocks.

```ruby
# BAD: Multiple levels
def process(orders)
  orders.each do |order|
    next unless order.valid?
    order.items.each do |item|
      process_item(item) if item.in_stock?
    end
  end
end

# GOOD: Extract methods
def process(orders)
  orders.select(&:valid?).each { |o| process_order(o) }
end
def process_order(order)
  order.items.select(&:in_stock?).each { |item| process_item(item) }
end
```

### 2. Don't Use ELSE When Guard Clauses Work
Use early returns.

```ruby
# BAD: else
def discount(user)
  if user.premium?
    20
  else
    0
  end
end

# GOOD: Early return
def discount(user)
  return 20 if user.premium?
  0
end
```

### 3. Wrap Primitives in Value Objects
Use value objects for domain concepts (Email, Money, UserId).

```ruby
# BAD: Primitive obsession
def create_user(email, age)
  raise unless email.include?('@')
  raise if age < 0
end

# GOOD: Value objects
class Email
  def initialize(value)
    raise InvalidEmail unless value.match?(/\A[^@]+@[^@]+\z/)
    @value = value.freeze
  end
  attr_reader :value
end
def create_user(email:, age:)
  # email is Email, age is Integer with validation elsewhere or Age value object
end
```

### 4. First-Class Collections
Any class that has a collection should expose behavior on the collection, not the raw array.

```ruby
# BAD: Raw array + other ivars
class Order
  attr_accessor :items, :customer_id, :total
end

# GOOD: Collection as its own abstraction
class OrderItems
  def initialize(items = [])
    @items = items
  end
  def add(item); end
  def total; end
  def empty?; end
end
class Order
  def initialize(items:, customer_id:)
    @items = items  # OrderItems
    @customer_id = customer_id
  end
end
```

### 5. One Dot per Line (Law of Demeter)
Don't chain through object graphs.

```ruby
# BAD: Train wreck
city = order.customer.address.city

# GOOD: Tell, don't ask
city = order.shipping_city
```

### 6. Keep Entities Small
- Classes: < 50 lines
- Methods: < 10 lines

### 7. No More Than Two Instance Variables per Class
Favor composition; group related state into value objects or small objects.

### 8. Tell, Don't Ask
Objects should have behavior. Don't query then decide elsewhere.

```ruby
# BAD: Ask then do
if account.balance >= amount
  account.balance = account.balance - amount
end

# GOOD: Tell
result = account.withdraw(amount)
```

---

## Comments

**Only write comments to explain WHY, not WHAT or HOW.** Prefer self-documenting names.

```ruby
# BAD: Explains what
# Add 1 to counter
counter += 1

# GOOD: Explains why
# Compensate for 0-based indexing in legacy API
counter += 1
```

## Storytelling

Code should read top-to-bottom. Public API first, then private methods in order of use.
