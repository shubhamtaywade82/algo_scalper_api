# AI Integration Guide

This document describes the AI integration module for the trading system, which provides AI-powered analysis and insights using OpenAI's API.

## Overview

The AI integration supports multiple providers:
- **Development/Test**: Uses `ruby-openai` gem (alexrudall/ruby-openai) - more features, easier debugging
- **Production**: Uses `openai-ruby` gem (official OpenAI SDK) - official support, production-ready
- **Ollama**: Local/network Ollama instance - free, private, runs on your hardware

## Configuration

### 1. Environment Variables

Set one of these environment variables with your OpenAI API key:

```bash
# Option 1: OPENAI_API_KEY (works with both gems)
export OPENAI_API_KEY="sk-..."

# Option 2: OPENAI_ACCESS_TOKEN (ruby-openai specific)
export OPENAI_ACCESS_TOKEN="sk-..."
```

### 2. Provider Selection

The provider is automatically selected based on environment:

- **Ollama**: Automatically selected if `OLLAMA_BASE_URL` is set
- **Development/Test**: `ruby-openai` (alexrudall)
- **Production**: `openai-ruby` (official)

You can override this by setting:

```bash
export OPENAI_PROVIDER="ollama"       # Use Ollama
export OPENAI_PROVIDER="ruby_openai"  # Use ruby-openai
export OPENAI_PROVIDER="openai_ruby"  # Use official gem
```

### 3. Ollama Configuration (Optional)

If you have Ollama running on another machine (e.g., Omarchy OS laptop):

```bash
# Set Ollama server URL (replace with your Ollama server IP)
export OLLAMA_BASE_URL="http://192.168.1.100:11434"

# Optional: Set default model
export OLLAMA_MODEL="llama3"

# Optional: API key (default: 'ollama')
export OLLAMA_API_KEY="ollama"
```

See [Ollama Setup Guide](OLLAMA_SETUP.md) for detailed instructions.

### 4. Enable in Config

Edit `config/algo.yml`:

```yaml
ai:
  enabled: true  # Set to true to enable AI integration
```

## Usage

### Basic Chat Completion

```ruby
client = Services::Ai::OpenaiClient.instance

response = client.chat(
  messages: [
    { role: 'user', content: 'Analyze today\'s trading performance' }
  ],
  model: 'gpt-4o',
  temperature: 0.7
)

puts response
```

### Streaming Chat

```ruby
client.chat_stream(
  messages: [
    { role: 'user', content: 'Explain trading strategy' }
  ],
  model: 'gpt-4o'
) do |chunk|
  print chunk
end
```

### Trading Analysis

```ruby
# Analyze a trading day
analysis = Services::Ai::TradingAnalyzer.analyze_trading_day(date: Date.today)

# Get strategy improvement suggestions
suggestions = Services::Ai::TradingAnalyzer.suggest_strategy_improvements(
  performance_data: {
    win_rate: 55.0,
    realized_pnl: 15000,
    total_trades: 100
  }
)
```

## Rake Tasks

### Analyze Trading Day

```bash
# Analyze today
bundle exec rake ai:analyze_day

# Analyze specific date
DATE=2025-12-18 bundle exec rake ai:analyze_day
```

### Strategy Improvements

```bash
bundle exec rake ai:suggest_improvements
```

### Test Connection

```bash
bundle exec rake ai:test
```

## Architecture

### Services

1. **`Services::Ai::OpenaiClient`**
   - Abstraction layer for both OpenAI gems
   - Provides unified interface
   - Handles provider selection and initialization
   - Note: Class name is `OpenaiClient` (not `OpenAIClient`) to match Zeitwerk conventions

2. **`Services::Ai::TradingAnalyzer`**
   - Trading-specific AI analysis
   - Analyzes trading performance
   - Suggests strategy improvements
   - Analyzes market conditions

### File Structure

```
lib/services/ai/
  ├── openai_client.rb      # Client abstraction
  └── trading_analyzer.rb   # Trading analysis service

config/initializers/
  └── ai_client.rb          # Client initialization

lib/tasks/
  └── ai_analysis.rake      # Rake tasks
```

## Provider Differences

### ruby-openai (Development)

- More features and flexibility
- Better error messages
- Easier debugging
- Community-maintained

### openai-ruby (Production)

- Official OpenAI SDK
- Production-tested
- Official support
- Type-safe with Sorbet

## Error Handling

The AI client handles errors gracefully:

- Missing API key: Logs warning, disables client
- API errors: Logs error, returns nil
- Network errors: Logs error, returns nil

All errors are logged with context for debugging.

## Best Practices

1. **API Key Security**
   - Never commit API keys to version control
   - Use environment variables
   - Use Rails encrypted credentials for production

2. **Cost Management**
   - Monitor token usage
   - Use appropriate models (gpt-4o vs gpt-4-turbo)
   - Cache responses when possible
   - Set reasonable temperature values

3. **Error Handling**
   - Always check if client is enabled before use
   - Handle nil responses gracefully
   - Log errors for debugging

4. **Performance**
   - Use streaming for long responses
   - Batch requests when possible
   - Cache analysis results

## Examples

### Custom Analysis

```ruby
client = Services::Ai::OpenaiClient.instance

if client.enabled?
  response = client.chat(
    messages: [
      {
        role: 'system',
        content: 'You are a trading analyst.'
      },
      {
        role: 'user',
        content: 'Analyze this trade data: ...'
      }
    ],
    model: 'gpt-4o',
    temperature: 0.3
  )

  puts response
end
```

### Integration with Trading Stats

```ruby
# In a service or controller
stats = PositionTracker.paper_trading_stats_with_pct(date: Time.zone.today)

if Services::Ai::OpenaiClient.instance.enabled?
  analysis = Services::Ai::TradingAnalyzer.analyze_trading_day(date: Time.zone.today)

  if analysis
    # Send to Telegram, store in database, etc.
    Notifications::TelegramNotifier.instance.send_message(analysis[:analysis])
  end
end
```

## Troubleshooting

### Client Not Enabled

**Problem**: `Services::Ai::OpenaiClient.instance.enabled?` returns false

**Solutions**:
1. Check if API key is set: `echo $OPENAI_API_KEY`
2. Check config: `config/algo.yml` should have `ai.enabled: true`
3. Check logs for initialization errors

### Provider Issues

**Problem**: Wrong provider being used

**Solution**: Set `OPENAI_PROVIDER` environment variable:
```bash
export OPENAI_PROVIDER="ruby_openai"  # or "openai_ruby"
```

### API Errors

**Problem**: API calls failing

**Solutions**:
1. Verify API key is valid
2. Check API rate limits
3. Review error logs for specific error messages
4. Ensure network connectivity

## Future Enhancements

Potential future additions:
- Fine-tuned models for trading-specific analysis
- Vector store integration for historical data
- Real-time market sentiment analysis
- Automated strategy optimization suggestions
- Risk assessment using AI
