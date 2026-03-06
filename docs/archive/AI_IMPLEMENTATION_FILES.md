# AI Implementation Files - Complete Reference

## 📁 Core AI Services

### 1. **lib/services/ai.rb**
   - **Purpose**: Module definition for `Services::Ai` namespace
   - **Content**: Empty module to satisfy Zeitwerk autoloading requirements
   - **Dependencies**: None

### 2. **lib/services/ai/openai_client.rb**
   - **Purpose**: OpenAI API client abstraction layer
   - **Key Features**:
     - Supports multiple providers: `ruby-openai`, `openai-ruby`, Ollama
     - Auto-detects and selects best Ollama model
     - Streaming support for chat completions
     - Singleton pattern (`Services::Ai::OpenaiClient.instance`)
   - **Methods**:
     - `chat(messages:, model:, temperature:)` - Non-streaming chat
     - `chat_stream(messages:, model:, temperature:, &block)` - Streaming chat
     - `fetch_available_models` - Get Ollama models
     - `select_best_model` - Auto-select optimal model
   - **Configuration**: Uses `OLLAMA_BASE_URL`, `OLLAMA_MODEL`, `OLLAMA_TIMEOUT`

### 3. **lib/services/ai/technical_analysis_agent.rb**
   - **Purpose**: Main AI agent for technical analysis with function calling
   - **Key Features**:
     - Function calling (tool use) implementation
     - Comprehensive analysis tool (`get_comprehensive_analysis`)
     - All technical indicator calculations
     - Learning/error tracking (Redis-backed)
     - Dynamic iteration limits
     - Streaming support
   - **Tools Available**:
     - `get_comprehensive_analysis` - All data in one call
     - `get_index_ltp` - Index LTP
     - `get_instrument_ltp` - Instrument LTP
     - `get_ohlc` - OHLC data
     - `get_historical_data` - Historical candles
     - `calculate_indicator` - Single indicator
     - `analyze_option_chain` - Option chain analysis
     - `get_trading_stats` - Trading statistics
     - `get_active_positions` - Active positions
     - `calculate_advanced_indicator` - HolyGrail, TrendDuration
     - `run_backtest` - Backtesting
     - `optimize_indicator` - Indicator optimization
   - **Methods**:
     - `analyze(query:, stream: false, &block)` - Main entry point
     - `execute_conversation_stream` - Streaming conversation handler
     - `execute_tool(tool_name, args)` - Tool execution
     - `detect_exchange_for_index` - Auto-detect exchange
     - `detect_segment_for_symbol` - Auto-detect segment (index vs equity)
   - **Configuration**: Uses `AI_AGENT_MAX_ITERATIONS`, `AI_AGENT_MAX_CONSECUTIVE_TOOLS`, `AI_AGENT_STREAM_TIMEOUT`

### 4. **lib/services/ai/trading_analyzer.rb**
   - **Purpose**: AI-powered trading data analysis
   - **Key Features**:
     - Analyzes trading day performance
     - Suggests strategy improvements
     - Analyzes market conditions
     - Streaming support
   - **Methods**:
     - `analyze_trading_day(date:, stream: false, &block)`
     - `suggest_strategy_improvements(performance_data:, stream: false, &block)`
     - `analyze_market_conditions(market_data:, stream: false, &block)`

---

## ⚙️ Configuration Files

### 5. **config/initializers/ai_client.rb**
   - **Purpose**: Initialize AI client on application startup
   - **Content**: Rails initializer that loads `Services::Ai::OpenaiClient` and logs status
   - **Runs**: After Rails application initialization

### 6. **config/algo.yml**
   - **Purpose**: Main configuration file
   - **AI Section**: Lines ~520-550
   - **Configuration Options**:
     - `ai.enabled` - Enable/disable AI integration
     - Comments for environment variables:
       - `OLLAMA_BASE_URL`
       - `OLLAMA_MODEL`
       - `OLLAMA_TIMEOUT`
       - `AI_AGENT_MAX_ITERATIONS`
       - `AI_AGENT_MAX_CONSECUTIVE_TOOLS`
       - `AI_AGENT_STREAM_TIMEOUT`

---

## 🔧 Rake Tasks

### 7. **lib/tasks/ai_analysis.rake**
   - **Tasks**:
     - `ai:test` - Test AI integration
     - `ai:list_models` - List available Ollama models
     - `ai:analyze_day [DATE]` - Analyze trading day using AI
     - `ai:suggest_improvements` - Get AI suggestions for strategy improvements
   - **Usage**: `bundle exec rake ai:analyze_day DATE=2025-12-19`

### 8. **lib/tasks/ai_technical_analysis.rake**
   - **Tasks**:
     - `ai:technical_analysis["query"]` - Main technical analysis task
     - `ai:examples` - Show example prompts and capabilities
   - **Usage**:
     - `bundle exec rake 'ai:technical_analysis["What is the current trend for NIFTY?"]'`
     - `STREAM=true bundle exec rake 'ai:technical_analysis["query"]'` - With streaming

---

## 📚 Documentation Files

### 9. **docs/AI_INTEGRATION.md**
   - **Purpose**: Complete AI integration guide
   - **Content**:
     - Setup instructions
     - Configuration details
     - Environment variables
     - Provider selection (OpenAI vs Ollama)
     - Usage examples

### 10. **docs/TECHNICAL_ANALYSIS_AGENT.md**
   - **Purpose**: Technical Analysis Agent documentation
   - **Content**:
     - Agent overview
     - Available tools
     - Tool descriptions
     - Usage examples
     - Best practices

### 11. **docs/OLLAMA_SETUP.md**
   - **Purpose**: Ollama setup guide
   - **Content**:
     - Installation instructions
     - CPU-only mode setup
     - Model recommendations
     - Performance tips
     - Network configuration

### 12. **docs/AI_SERVICE_ISOLATION.md**
   - **Purpose**: Confirms AI services don't interfere with trading
   - **Content**: Architecture explanation showing AI services are isolated

---

## 📦 Dependencies

### 13. **Gemfile**
   - **AI Gems**:
     - `ruby-openai` (~> 8.0) - Development/test environment
     - `openai` (~> 0.41) - Production environment
   - **Both support**: Ollama (OpenAI-compatible API)

---

## 🐳 Docker Configuration

### 14. **docker-compose.ollama.yml**
   - **Purpose**: Docker Compose configuration for Ollama
   - **Features**:
     - CPU-only mode support (`OLLAMA_NUM_GPU=0`)
     - Health checks
     - Volume persistence
     - Network configuration
   - **Usage**: `docker-compose -f docker-compose.ollama.yml up -d`

---

## 🔌 Environment Variables

### Required (at least one):
- `OPENAI_API_KEY` or `OPENAI_ACCESS_TOKEN` - For OpenAI API
- `OLLAMA_BASE_URL` - For Ollama (e.g., `http://192.168.1.14:11434`)

### Optional:
- `OLLAMA_MODEL` - Explicitly set Ollama model (e.g., `llama3.2:3b`)
- `OLLAMA_TIMEOUT` - Timeout for Ollama requests (default: 300 seconds)
- `AI_AGENT_MAX_ITERATIONS` - Max iterations before safety limit (default: 15, range: 3-100)
- `AI_AGENT_MAX_CONSECUTIVE_TOOLS` - Max consecutive tool calls (default: 8, range: 3-15)
- `AI_AGENT_STREAM_TIMEOUT` - Stream timeout per iteration (default: 60 seconds)
- `OPENAI_PROVIDER` - Override provider: `ruby_openai`, `openai_ruby`, or `ollama`

---

## 📊 Data Flow

```
User Query
    ↓
TechnicalAnalysisAgent.analyze()
    ↓
OpenaiClient.chat_stream() / chat()
    ↓
Ollama/OpenAI API
    ↓
Tool Calls (if needed)
    ↓
Tool Execution (e.g., get_comprehensive_analysis)
    ↓
Indicator Calculations
    ↓
Response with interpretations
    ↓
AI Analysis
    ↓
Final Response
```

---

## 🔗 Integration Points

### AI Services Use:
- `Instrument` model - For instrument lookups
- `InstrumentHelpers` concern - For historical data, indicators
- `IndexConfigLoader` - For index configuration
- `CandleSeries` - For technical indicators
- `PositionTracker` - For trading statistics
- `Options::DerivativeChainAnalyzer` - For option chain analysis
- `BacktestService` - For backtesting
- `Indicators::Calculator` - For indicator calculations
- Redis - For learned patterns and error history

### AI Services Do NOT Use:
- Trading execution services
- Order placement
- Position management
- Risk management
- Signal generation

---

## 📝 File Summary

| Category      | Count  | Files                                                                                            |
| ------------- | ------ | ------------------------------------------------------------------------------------------------ |
| Core Services | 4      | `ai.rb`, `openai_client.rb`, `technical_analysis_agent.rb`, `trading_analyzer.rb`                |
| Configuration | 2      | `ai_client.rb` (initializer), `algo.yml`                                                         |
| Rake Tasks    | 2      | `ai_analysis.rake`, `ai_technical_analysis.rake`                                                 |
| Documentation | 4      | `AI_INTEGRATION.md`, `TECHNICAL_ANALYSIS_AGENT.md`, `OLLAMA_SETUP.md`, `AI_SERVICE_ISOLATION.md` |
| Docker        | 1      | `docker-compose.ollama.yml`                                                                      |
| **Total**     | **13** | **Core AI implementation files**                                                                 |

---

## 🎯 Quick Reference

### Main Entry Points:
1. **Technical Analysis**: `Services::Ai::TechnicalAnalysisAgent.analyze(query:, stream: false)`
2. **Trading Analysis**: `Services::Ai::TradingAnalyzer.analyze_trading_day(date:, stream: false)`
3. **Client Access**: `Services::Ai::OpenaiClient.instance`

### Rake Task Commands:
```bash
# Technical analysis
bundle exec rake 'ai:technical_analysis["What is the trend for NIFTY?"]'

# With streaming
STREAM=true bundle exec rake 'ai:technical_analysis["query"]'

# Show examples
bundle exec rake ai:examples

# Analyze trading day
bundle exec rake ai:analyze_day DATE=2025-12-19

# List Ollama models
bundle exec rake ai:list_models
```

---

*Last Updated: 2025-12-19*
