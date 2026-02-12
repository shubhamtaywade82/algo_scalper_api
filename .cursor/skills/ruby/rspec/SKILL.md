---
name: rspec
description: RSpec best practices from the RSpec Style Guide and Better Specs. Use when writing or reviewing RSpec specs, request specs, model specs, or integration tests in Ruby/Rails projects.
---

# RSpec Style Guide & Best Practices

This skill applies the [RSpec Style Guide](https://rspec.rubystyle.guide/) and [Better Specs](https://www.betterspecs.org/). [RuboCop RSpec](https://github.com/rubocop/rubocop-rspec) enforces many of these rules.

Use when writing or reviewing RSpec examples, request specs, model specs, or integration tests.

---

## Layout

- **No empty line** after `describe`/`context`/`feature` opening — start the block body immediately.
- **One empty line** between sibling `describe`/`context` blocks; none after the last block in a group.
- **One empty line** after `subject`, `let`, and `before`/`after` blocks.
- **Group** `subject` and `let` blocks together; separate them from `before`/`after` with a blank line.
- **One empty line** around each `it`/`specify` block to separate expectations from context.

```ruby
# good
describe Article do
  subject { FactoryBot.create(:article) }
  let(:user) { FactoryBot.create(:user) }

  before do
    # ...
  end

  describe '#summary' do
    context 'when there is a summary' do
      it 'returns the summary' do
        # ...
      end
    end

    context 'when there is no summary' do
      it 'returns nil' do
        # ...
      end
    end
  end
end
```

---

## Example Group Structure

- **Order:** Declare in this order: `subject`, then `let!`/`let`, then `before`/`after`. Put `subject` first when used.
- **Contexts:** Use `context` to group examples. Start with **when**, **with**, or **without**. Prefer having a matching negative case (e.g. "when X" and "when not X").
- **let / let!:** Use `let` for data shared across examples; use `let!` when the value must exist before the example runs (e.g. for scopes). Prefer `let` over instance variables (`@var`).
- **Shared examples:** Use `shared_examples` / `it_behaves_like` to DRY repeated behavior. Don't over-DRY early; duplication in specs is acceptable for clarity.
- **Hooks:** Don't specify `:each` (it's the default). Use `:context` instead of `:all` when you need scope; avoid `before(:context)` when possible (state leakage).
- **No `it` in iterators:** Don't generate examples in a loop; write each `describe`/`it` explicitly so changes are localized.

```ruby
# bad
[:new, :show, :index].each do |action|
  it 'returns 200' do
    get action
    expect(response).to be_ok
  end
end

# good – separate describe per action
describe 'GET new' do
  it 'returns 200' do
    get :new
    expect(response).to be_ok
  end
end
```

---

## Describe Your Methods

Use the Ruby documentation convention: **`.`** (or `::`) for class methods, **`#`** for instance methods.

```ruby
# bad
describe 'the authenticate method for User'
describe 'if the user is an admin'

# good
describe '.authenticate'
describe '#admin?'
```

---

## Use Contexts

Group with `context`; full example names (all block descriptions concatenated) should read as a sentence.

```ruby
# bad
it 'has 200 status code if logged in' do
  expect(response).to respond_with 200
end

# good
context 'when logged in' do
  it { is_expected.to respond_with 200 }
end
context 'when logged out' do
  it { is_expected.to respond_with 401 }
end
```

---

## Subject

- Use **`subject`** when several examples relate to the same object under test.
- Prefer **named subject** when you reference it: `subject(:article) { ... }` and `expect(article).to ...`. Use anonymous `subject` only when you use `is_expected` and never reference the subject by name.
- In nested contexts, if you reassign subject with different data, give it a different name (e.g. `guest_article`) so intent is clear.
- **Don't stub the subject:** If you stub methods on the object under test, fix the design (e.g. inject dependencies or use a different subject) instead.

```ruby
# good – named subject
describe Article do
  subject(:article) { FactoryBot.create(:article) }
  it 'is not published on creation' do
    expect(article).not_to be_published
  end
end

# good – anonymous when using is_expected
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

---

## Example Structure

- **Expectation per example:** In isolated unit specs, prefer one expectation per example. For non-isolated specs (DB, HTTP, integration), multiple expectations in one example are acceptable; consider `:aggregate_failures` when you have several.
- **Example descriptions:** Don't end with a conditional (e.g. "returns X if Y"); put the condition in a `context` and keep the example description about the outcome. Keep descriptions under ~60 characters; use `context` to split.
- **No "should" in descriptions:** Use third person, present tense. Don't start with "should" or "should not".

```ruby
# bad
it 'should return the summary'
it 'returns the summary if it is present'

# good
context 'when display name is present' do
  it 'returns the display name' do
    # ...
  end
end
it 'returns the summary'
it 'does not change timings'
```

---

## Expect Syntax

Use **`expect`** only; never `should`. For one-liners with implicit subject, use **`is_expected.to`**.

```ruby
# bad
response.should respond_with_content_type(:json)
it { should respond_with 422 }

# good
expect(response).to respond_with_content_type(:json)
it { is_expected.to respond_with 422 }
```

Configure RSpec to enforce expect syntax:

```ruby
# spec_helper.rb or rails_helper.rb
RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
```

---

## let and let!

Prefer **`let`** over `before { @var = ... }`. Use **`let!`** when the value must exist before the example (e.g. testing scopes or queries). Don't overuse `let` for trivial primitives; balance reuse vs. clarity.

```ruby
# bad
before { @resource = FactoryBot.create(:device) }

# good
let(:resource) { FactoryBot.create(:device) }
let!(:user) { FactoryBot.create(:user) }  # when you need it loaded before the example
```

---

## Matchers

- **Predicate matchers:** Prefer RSpec's predicate matchers: `expect(article).to be_published` instead of `expect(article.published?).to be true`.
- **Built-in matchers:** Use built-in matchers (e.g. `include`, `eq`) instead of hand-rolled expectations.
- **Avoid bare `be`:** Don't use `expect(x).to be`; use `be_truthy`, `be_nil`, or a specific matcher (e.g. `be_an(Author)`).
- **Custom matchers:** Extract repeated expectation logic into custom matchers (or use libraries like Shoulda Matchers).
- **No `any_instance_of`:** Avoid `allow_any_instance_of` / `expect_any_instance_of`; stub or inject the dependency instead.
- **Block expectations:** Prefer explicit block form: `expect { do_something }.to change(something).to(new_value)` over implicit subject with a lambda.

```ruby
# bad
expect(article.published?).to be true
expect(article.author).to be

# good
expect(article).to be_published
expect(article.author).to be_truthy
expect(article.author).to be_an(Author)
```

---

## Doubles and Stubbing

- **Verifying doubles:** Prefer `instance_double`, `object_double`, `class_double`, and verifying partial doubles over non-verifying doubles. Keep `verify_partial_doubles` enabled.
- **Don't stub subject:** Don't stub methods on the object under test; fix design or use a different subject (e.g. a presenter that receives the collaborator).
- **Mock sparingly:** Prefer real behavior when possible; use doubles to isolate external dependencies (DB, HTTP). If stubbing could hide a real bug, you've gone too far.
- **Constants:** Don't define classes/modules/constants inside example groups (they leak). Use `stub_const` or anonymous `Class.new` and assign to a `let`.

---

## Time and HTTP

- **Time:** Use **Timecop** (or `ActiveSupport::Testing::TimeHelpers#freeze_time`) instead of stubbing `Time.now` / `Date`.
- **HTTP:** Stub external HTTP (e.g. **WebMock**, **VCR**) so specs don't hit real services.

---

## Data and Factories

- **Needed data only:** Create only the data the example needs. Avoid dozens of records unless the test truly needs them.
- **Factories over fixtures:** Use **Factory Bot** (or similar), not fixtures. In unit tests, prefer minimal setup or objects built in the spec.
- **Incidental state:** Avoid depending on incidental state (e.g. "there are exactly 2 articles"); use `change(Article, :count).by(1)` or similar so the example is self-contained.

---

## Rails: Integration, Controllers, Models, Views, Mailers

- **Integration over controller specs:** Prefer integration/request specs that test behavior; don't add controller specs just for coverage if integration tests suffice.
- **Controllers:** Mock models and stub their methods; test only controller responsibility (assigns, redirects, template, status). Use contexts for success vs. failure (e.g. "when the article saves" / "when the article fails to save").
- **Models:** Don't mock the model under test. Use `FactoryBot.create` or a new instance. Add an example that the factory-built model is valid. For validations, use `expect(model.errors[:attr].size).to eq(1)` (or a matcher) so the right attribute is validated. Name the other object in uniqueness specs `another_article` (or similar).
- **Views:** Mock models in view specs. Use `assign` for instance variables. Prefer Capybara negative selectors (`have_no_selector`) over `not_to have_selector`. Stub helpers on `template` when the view uses them.
- **Mailers:** Mock the model; verify subject, from, to, and body content.

---

## Summary Checklist

- [ ] Layout: no empty line after describe/context; one between sibling groups; blank after let/subject/before; one around each it
- [ ] Order: subject, then let/let!, then before/after
- [ ] Describe with `.method` or `#method`; context with when/with/without
- [ ] Short example descriptions; no "should"; no conditional in the it string (use context)
- [ ] One expectation per example in unit specs; use expect / is_expected only
- [ ] Named subject when referenced; don't stub subject
- [ ] Prefer verifying doubles; no any_instance_of
- [ ] Time: Timecop/freeze_time; HTTP: WebMock/VCR
- [ ] Minimal data; factories not fixtures; no it in iterators
- [ ] Shared examples where they reduce duplication without obscuring intent

---

## References

- [RSpec Style Guide](https://rspec.rubystyle.guide/) — layout, structure, naming, matchers, Rails
- [Better Specs](https://www.betterspecs.org/) — Rails testing practices (Lelylan Labs)
- [RSpec](https://rspec.info/) · [RuboCop RSpec](https://github.com/rubocop/rubocop-rspec)
