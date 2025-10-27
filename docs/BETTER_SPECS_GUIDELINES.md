# Better Specs Guidelines

This document outlines the Better Specs best practices we follow for testing in the Algo Scalper API project.

Source: https://www.betterspecs.org/

## Key Principles

### 1. Describe Your Methods
Use Ruby documentation conventions:
- `.` or `::` for class methods
- `#` for instance methods

**Example:**
```ruby
describe '.authenticate' do
describe '#admin?' do
```

### 2. Use Contexts
Always use contexts to organize tests. Start context descriptions with:
- `when`
- `with` / `without`
- `if` / `unless`
- `for`
- `that`

**Example:**
```ruby
context 'when logged in' do
  it { is_expected.to respond_with 200 }
end

context 'when logged out' do
  it { is_expected.to respond_with 401 }
end
```

### 3. Keep Descriptions Short
Spec descriptions should never exceed 40 characters. Split longer tests using contexts.

**Bad:**
```ruby
it 'has 422 status code if an unexpected params will be added' do
```

**Good:**
```ruby
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

### 4. Single Expectation
Each test should make only one assertion for isolated unit tests.

**Good (isolated):**
```ruby
it { is_expected.to respond_with_content_type(:json) }
it { is_expected.to assign_to(:resource) }
```

**Good (not isolated - integration tests):**
```ruby
it 'creates a resource' do
  expect(response).to respond_with_content_type(:json)
  expect(response).to assign_to(:resource)
end
```

### 5. Test All Possible Cases
Test valid, edge, and invalid cases.

**Example:**
```ruby
describe '#destroy' do
  context 'when resource is found' do
    it 'responds with 200'
    it 'shows the resource'
  end

  context 'when resource is not found' do
    it 'responds with 404'
  end

  context 'when resource is not owned' do
    it 'responds with 404'
  end
end
```

### 6. Use Expect Syntax (Not Should)
Always use `expect` syntax, not `should`.

**Bad:**
```ruby
it 'creates a resource' do
  response.should respond_with_content_type(:json)
end
```

**Good:**
```ruby
it 'creates a resource' do
  expect(response).to respond_with_content_type(:json)
end
```

For implicit subject use `is_expected.to`:
```ruby
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

### 7. Use Subject
Use `subject` to DRY up tests related to the same subject.

**Bad:**
```ruby
it { expect(assigns('message')).to match /it was born in Belville/ }
```

**Good:**
```ruby
subject { assigns('message') }
it { is_expected.to match /it was born in Billville/ }
```

Named subject:
```ruby
subject(:hero) { Hero.first }
it "carries a sword" do
  expect(hero.equipment).to include "sword"
end
```

### 8. Use let and let!
Use `let` for lazy-loaded variables. Use `let!` when you need eager evaluation.

**Bad:**
```ruby
describe '#type_id' do
  before { @resource = FactoryBot.create :device }
  before { @type     = Type.find @resource.type_id }
  it 'sets the type_id field' do
    expect(@resource.type_id).to eq(@type.id)
  end
end
```

**Good:**
```ruby
describe '#type_id' do
  let(:resource) { FactoryBot.create :device }
  let(:type)     { Type.find resource.type_id }
  it 'sets the type_id field' do
    expect(resource.type_id).to eq(type.id)
  end
end
```

### 9. Don't Overuse Mocks
As a general rule, don't (over)use mocks. Test real behavior when possible.

### 10. Create Only the Data You Need
Don't load more data than needed for your tests.

**Good:**
```ruby
describe ".top" do
  before { FactoryBot.create_list(:user, 3) }
  it { expect(User.top(2)).to have(2).item }
end
```

### 11. Use Factories (Not Fixtures)
Use Factory Bot to reduce verbosity when creating test data.

**Bad:**
```ruby
user = User.create(
  name: 'Genoveffa',
  surname: 'Piccolina',
  city: 'Billyville',
  birth: '17 Agoust 1982',
  active: true
)
```

**Good:**
```ruby
user = FactoryBot.create :user
```

### 12. Use Easy-to-Read Matchers
Use readable matchers from RSpec.

**Bad:**
```ruby
lambda { model.save! }.to raise_error Mongoid::Errors::DocumentNotFound
```

**Good:**
```ruby
expect { model.save! }.to raise_error Mongoid::Errors::DocumentNotFound
```

### 13. Don't Use "Should"
Do not use "should" in test descriptions. Use third person present tense.

**Bad:**
```ruby
it 'should not change timings' do
  consumption.occur_at.should == valid.occur_at
end
```

**Good:**
```ruby
it 'does not change timings' do
  expect(consumption.occur_at).to eq(valid.occur_at)
end
```

## Configuration

Our `.rubocop.yml` enforces these guidelines with the following cops:

- `RSpec/ContextWording`: Enforces contexts starting with `when`, `with`, `without`, etc.
- `RSpec/SingleExpectation`: Enforced for unit tests, relaxed for integration/system tests
- `RSpec/NestedGroups`: Max 5 levels deep
- `RSpec/MultipleMemoizedHelpers`: Max 10 helpers
- `Layout/LineLength`: Max 120 characters with specific exclusions

## Additional Resources

- [Better Specs Website](https://www.betterspecs.org/)
- [RSpec Documentation](https://rspec.info/)
- [Factory Bot Documentation](https://github.com/thoughtbot/factory_bot)

