# Ferment Exchange Emulator - Implementation Notes

## Project Overview

Ferment is a centralized paper exchange emulator for trading strategy development and backtesting.

## Phase 1: Foundation

**Step 1: Monorepo Structure** ✓

Created directory structure:
```
ecosystem/
├── apps/
│   ├── api/           # Rails 8 control plane
│   ├── exchange/      # Go execution engine  
│   └── marketfeed/    # Go market data adapter
├── libs/
│   └── contracts/     # Shared schemas
└── infrastructure/    # Docker, NATS, PostgreSQL
```

**Step 2: Next Steps (pending)**
- Initialize Rails app with proper structure
- Create Go module files
- Define Protocol Buffer schemas
- Implement core exchange components