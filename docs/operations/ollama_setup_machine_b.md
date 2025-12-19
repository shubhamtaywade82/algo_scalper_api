# Ollama Client Setup - Machine B

**Purpose:** Send requests to Ollama server. Never blocks. Never hangs.

**Machine:** Windows / WSL / Dev Laptop (any machine running Rails)

---

## B1. Set Remote Ollama Endpoint

### Linux / WSL

```bash
export OLLAMA_HOST=http://192.168.0.200:11434
```

Add to `~/.bashrc` or `~/.zshrc` for persistence:

```bash
echo 'export OLLAMA_HOST=http://192.168.0.200:11434' >> ~/.bashrc
```

### Windows (PowerShell)

```powershell
$env:OLLAMA_HOST="http://192.168.0.200:11434"
```

Add to PowerShell profile for persistence:

```powershell
[System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', 'http://192.168.0.200:11434', 'User')
```

### Rails Application (config/application.rb or .env)

Add to `.env` file:

```
OLLAMA_HOST=http://192.168.0.200:11434
```

> **Replace `192.168.0.200` with your current server IP**  
> (or use Tailscale IP if you enable it: `http://100.x.y.z:11434`)

---

## B2. Client Usage Rules (IMPORTANT)

### ✅ DO

- Serialize requests (one at a time)
- Add small delays between calls (`sleep 0.5`)
- Use timeouts (already built into `OllamaClient`)
- Check `OllamaBusy.locked?` before calling
- Handle timeout errors gracefully

### ❌ DO NOT

- Fire parallel LLM calls
- Mix embeddings + chat concurrently
- Retry blindly without delays
- Ignore timeout errors
- Call Ollama from multiple threads simultaneously

---

## B3. Rails / Ruby Client Usage

### Basic Usage

```ruby
require 'providers/ollama_client'

# Generate text completion
result = Providers::OllamaClient.generate("What is the trend?", model: "phi3:mini")

if result == :ollama_timeout
  Rails.logger.warn("Ollama timeout - skipping")
elsif result == :ollama_error
  Rails.logger.error("Ollama error - skipping")
else
  # Use result (String)
  puts result
end
```

### With Lock Protection

```ruby
require 'providers/ollama_busy'
require 'providers/ollama_client'

# Check if busy before calling
return if Providers::OllamaBusy.locked?

# Use lock to prevent concurrent calls
result = Providers::OllamaBusy.with_lock do
  Providers::OllamaClient.generate(prompt, model: "phi3:mini")
end

# Handle result
if result == :ollama_timeout || result.nil?
  Rails.logger.warn("Ollama unavailable - skipping")
else
  # Process result
end
```

### Simplest Approach (Recommended)

```ruby
# Just add delay between calls
sleep 0.5

result = Providers::OllamaClient.generate(prompt)
```

---

## B4. Embeddings Client (SEPARATE FLOW)

```ruby
# Generate embeddings
embedding = Providers::OllamaClient.embed("Some text", model: "nomic-embed-text")

if embedding.is_a?(Array)
  # Use embedding vector
  puts "Embedding dimension: #{embedding.length}"
else
  # Handle error (:ollama_timeout, :ollama_error, etc.)
  Rails.logger.warn("Embedding failed: #{embedding}")
end
```

> 🚨 **Never call embeddings while chat inference is running.**

**Best Practice:** Use separate background jobs or ensure chat and embeddings are never called concurrently.

---

## B5. Client-Side Safety Guards (MANDATORY)

### Option 1: Lock Check (Recommended)

```ruby
return if Providers::OllamaBusy.locked?

Providers::OllamaBusy.with_lock do
  result = Providers::OllamaClient.generate(prompt)
  # Process result
end
```

### Option 2: Simple Delay (Simplest)

```ruby
sleep 0.5  # Small delay between calls
result = Providers::OllamaClient.generate(prompt)
```

### Option 3: Health Check First

```ruby
unless Providers::OllamaClient.health_check
  Rails.logger.warn("Ollama server unavailable - skipping")
  return
end

result = Providers::OllamaClient.generate(prompt)
```

---

## B6. Integration Examples

### In a Service Class

```ruby
# frozen_string_literal: true

class Signal::AnalysisService < ApplicationService
  def call(snapshot)
    # Check if Ollama is busy
    return analyze_without_llm(snapshot) if Providers::OllamaBusy.locked?

    # Use Ollama for analysis
    prompt = build_analysis_prompt(snapshot)
    llm_result = Providers::OllamaClient.generate(prompt, model: "phi3:mini")

    if llm_result == :ollama_timeout || llm_result == :ollama_error
      log_warn("Ollama unavailable - using fallback analysis")
      return analyze_without_llm(snapshot)
    end

    # Process LLM result
    parse_llm_analysis(llm_result)
  end

  private

  def analyze_without_llm(snapshot)
    # Fallback logic without LLM
  end
end
```

### In a Background Job

```ruby
# frozen_string_literal: true

class LlmAnalysisJob < ApplicationJob
  queue_as :default

  def perform(snapshot_id)
    snapshot = Snapshot.find(snapshot_id)
    
    # Add delay to prevent overwhelming server
    sleep 0.5

    result = Providers::OllamaClient.generate(
      build_prompt(snapshot),
      model: "phi3:mini"
    )

    if result.is_a?(String)
      process_result(snapshot, result)
    else
      Rails.logger.warn("[LlmAnalysisJob] Failed: #{result}")
      # Retry later or use fallback
    end
  end
end
```

---

## B7. Error Handling

### Timeout Handling

```ruby
result = Providers::OllamaClient.generate(prompt)

case result
when :ollama_timeout
  Rails.logger.warn("Ollama timeout - request took too long")
  # Use fallback or retry later
when :ollama_error
  Rails.logger.error("Ollama error - check server logs")
  # Use fallback
when :ollama_not_configured
  Rails.logger.warn("OLLAMA_HOST not set - skipping")
  # Use fallback
when String
  # Success - use result
  process_result(result)
else
  Rails.logger.error("Unexpected result: #{result.inspect}")
end
```

---

## B8. Health Check Endpoint

Add to your Rails health check:

```ruby
# config/routes.rb
namespace :api do
  get 'health', to: 'health_controller#show'
end

# app/controllers/api/health_controller.rb
class Api::HealthController < ApplicationController
  def show
    ollama_healthy = Providers::OllamaClient.health_check

    render json: {
      status: 'ok',
      ollama: ollama_healthy ? 'healthy' : 'unavailable',
      timestamp: Time.current.iso8601
    }
  end
end
```

---

## B9. Testing

### Mock Ollama in Tests

```ruby
# spec/spec_helper.rb or test helper
RSpec.configure do |config|
  config.before(:each) do
    allow(Providers::OllamaClient).to receive(:generate).and_return("Mock response")
    allow(Providers::OllamaClient).to receive(:health_check).and_return(true)
  end
end
```

### Test with Real Ollama (Integration Tests)

```ruby
# Set OLLAMA_HOST in test environment
# Only run if server is available

RSpec.describe Providers::OllamaClient, type: :integration do
  before do
    skip "Ollama server not available" unless Providers::OllamaClient.health_check
  end

  it "generates text" do
    result = Providers::OllamaClient.generate("Hello", model: "phi3:mini")
    expect(result).to be_a(String)
    expect(result).not_to eq(:ollama_timeout)
  end
end
```

---

## B10. Troubleshooting

### Connection Refused

```
Error: Connection refused
```

**Solution:**
1. Verify `OLLAMA_HOST` is set correctly
2. Check server IP hasn't changed (use Tailscale for stability)
3. Verify server is running: `curl http://192.168.0.200:11434/api/version`

### Timeout Errors

```
Result: :ollama_timeout
```

**Solution:**
1. Check server is not overloaded
2. Verify no other clients are making parallel requests
3. Increase timeout if needed (not recommended - indicates server issue)
4. Check server logs: `docker logs ollama`

### Lock Never Releases

```
OllamaBusy.locked? always returns true
```

**Solution:**
1. Lock auto-releases after 30 seconds
2. Manually release: `Providers::OllamaBusy.release_lock`
3. Check Redis is accessible
4. Verify no stuck processes holding lock

---

## Summary

**Client Configuration:**

- Set `OLLAMA_HOST` environment variable
- Use `Providers::OllamaClient` for all requests
- Serialize calls (no parallelism)
- Add delays between calls (`sleep 0.5`)
- Handle timeouts gracefully
- Never mix chat + embeddings concurrently
- Use `OllamaBusy` lock for critical sections

**Client Responsibilities:**

- All logic and orchestration
- Retry logic
- Error handling
- Fallback strategies
- Request serialization

**Decoupled Architecture:**

- If Ollama hangs → restart container (Machine A)
- If client fails → retry logic (Machine B)
- They are decoupled
