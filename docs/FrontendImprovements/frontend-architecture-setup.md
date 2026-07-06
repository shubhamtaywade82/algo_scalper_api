Perfect! Now I'll create a comprehensive Technical Design Document (TDD) for the **Algo Scalper** frontend.

---

# 📐 ALGO SCALPER - FRONTEND TECHNICAL DESIGN DOCUMENT

**Version:** 1.0
**Last Updated:** July 6, 2026
**Domain:** Algorithmic Trading Platform (Indian Stock Market - NSE Options)
**Broker Integration:** DhanHQ V2 API

---

## 📑 TABLE OF CONTENTS

1. [Architecture Overview](#1-architecture-overview)
2. [Technology Stack](#2-technology-stack)
3. [Project Structure](#3-project-structure)
4. [Layout System](#4-layout-system)
5. [Component Architecture](#5-component-architecture)
6. [Reusable UI Components](#6-reusable-ui-components)
7. [Domain-Specific Components](#7-domain-specific-components)
8. [State Management](#8-state-management)
9. [Routing & Navigation](#9-routing--navigation)
10. [API Integration Layer](#10-api-integration-layer)
11. [WebSocket Integration](#11-websocket-integration)
12. [TypeScript Interfaces](#12-typescript-interfaces)
13. [Styling System](#13-styling-system)
14. [Utilities & Helpers](#14-utilities--helpers)
15. [Performance Optimization](#15-performance-optimization)
16. [Testing Strategy](#16-testing-strategy)

---

## 1. ARCHITECTURE OVERVIEW

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER                        │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │   Layout    │  │    Pages     │  │  Reusable Components │   │
│  └─────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      STATE MANAGEMENT LAYER                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Redux/Zustand│ │ React Query  │ │  WebSocket Store     │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                       BUSINESS LOGIC LAYER                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Custom Hooks │  │   Services   │  │  Business Validators │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                        DATA ACCESS LAYER                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  REST API    │  │  WebSocket   │  │  Local Storage/Cache │  │
│  │   Client     │  │   Client     │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Design Principles

- **Component-Driven Development**: Atomic design methodology
- **Server-Driven UI**: Dynamic layouts from backend (for strategy builder)
- **Real-Time First**: WebSocket-first architecture for market data
- **Optimistic UI**: Immediate feedback for user actions
- **Progressive Enhancement**: Core functionality works without JS enhancements
- **Accessibility**: WCAG 2.1 AA compliance
- **Mobile-Responsive**: Tablet-first approach (trading is desktop-heavy but needs mobile)

---

## 2. TECHNOLOGY STACK

### 2.1 Core Framework & Libraries

```json
{
  "framework": "Next.js 14+ (App Router)",
  "language": "TypeScript 5.x",
  "styling": "Tailwind CSS 3.x + CSS Modules",
  "stateManagement": {
    "global": "Zustand (lightweight, fast)",
    "server": "TanStack Query (React Query) v5",
    "realtime": "Zustand + WebSocket middleware"
  },
  "routing": "Next.js App Router with Route Groups",
  "forms": "React Hook Form + Zod validation",
  "charts": {
    "primary": "TradingView Lightweight Charts",
    "general": "Recharts v2",
    "candlestick": "Lightweight Charts (TradingView)"
  },
  "tables": "TanStack Table v8",
  "dateHandling": "date-fns + date-fns-tz",
  "http": "Axios + custom interceptors",
  "websocket": "Native WebSocket API + retry logic"
}
```

### 2.2 UI Component Libraries

```typescript
// Base UI Components
- Radix UI Primitives (headless UI)
- shadcn/ui (pre-built accessible components)

// Specialized Components
- Monaco Editor (for strategy code editor)
- React Flow (for visual strategy builder)
- React Virtualized (for large tables/lists)
- React Grid Layout (for customizable dashboards)
```

### 2.3 Development Tools

```json
{
  "testing": {
    "unit": "Vitest + React Testing Library",
    "e2e": "Playwright",
    "coverage": "c8"
  },
  "linting": "ESLint + Prettier",
  "typeChecking": "tsc --noEmit",
  "bundleAnalysis": "@next/bundle-analyzer",
  "monitoring": "Sentry (error tracking)"
}
```

---

## 3. PROJECT STRUCTURE

```
algo-scalper-frontend/
├── app/                              # Next.js App Router
│   ├── (auth)/                       # Auth route group
│   │   ├── login/
│   │   └── register/
│   ├── (dashboard)/                  # Main app route group
│   │   ├── dashboard/
│   │   ├── market-watch/
│   │   ├── option-chain/
│   │   ├── positions/
│   │   ├── orders/
│   │   ├── holdings/
│   │   ├── funds/
│   │   ├── reports/
│   │   ├── strategies/
│   │   │   ├── creator/
│   │   │   └── [id]/
│   │   ├── backtester/
│   │   ├── replay/
│   │   ├── market-data/
│   │   ├── logs/
│   │   ├── alerts/
│   │   ├── scheduler/
│   │   └── settings/
│   ├── api/                          # API routes (if needed)
│   ├── layout.tsx                    # Root layout
│   ├── page.tsx                      # Root page (redirect)
│   └── globals.css                   # Global styles
│
├── components/
│   ├── ui/                           # Base UI components
│   │   ├── Button/
│   │   │   ├── Button.tsx
│   │   │   ├── Button.stories.tsx
│   │   │   └── index.ts
│   │   ├── Card/
│   │   ├── Table/
│   │   ├── Modal/
│   │   ├── Dropdown/
│   │   ├── Input/
│   │   ├── Select/
│   │   ├── Toggle/
│   │   ├── Badge/
│   │   ├── Tabs/
│   │   ├── Tooltip/
│   │   ├── Skeleton/
│   │   ├── Toast/
│   │   └── index.ts                  # Barrel export
│   │
│   ├── charts/                       # Chart components
│   │   ├── LineChart/
│   │   ├── AreaChart/
│   │   ├── CandlestickChart/
│   │   ├── DonutChart/
│   │   ├── BarChart/
│   │   ├── GaugeChart/
│   │   ├── VolumeProfile/
│   │   └── index.ts
│   │
│   ├── layout/                       # Layout components
│   │   ├── Sidebar/
│   │   ├── Header/
│   │   ├── Footer/
│   │   ├── PageContainer/
│   │   ├── Grid/
│   │   └── index.ts
│   │
│   ├── trading/                      # Domain-specific components
│   │   ├── KPICard/
│   │   ├── OrderBook/
│   │   ├── MarketDepth/
│   │   ├── OptionChain/
│   │   ├── PositionTable/
│   │   ├── OrderTable/
│   │   ├── TradeTicket/
│   │   ├── PLChart/
│   │   ├── EquityCurve/
│   │   ├── DrawdownChart/
│   │   ├── StrategyBuilder/
│   │   ├── CodeEditor/
│   │   ├── AlertCard/
│   │   ├── TaskCard/
│   │   └── index.ts
│   │
│   ├── forms/                        # Form components
│   │   ├── FormField/
│   │   ├── DatePicker/
│   │   ├── TimePicker/
│   │   ├── SearchInput/
│   │   ├── FilterBar/
│   │   └── index.ts
│   │
│   └── shared/                       # Shared components
│       ├── LoadingSpinner/
│       ├── ErrorBoundary/
│       ├── EmptyState/
│       ├── ConfirmDialog/
│       └── index.ts
│
├── features/                         # Feature-based modules
│   ├── auth/
│   │   ├── components/
│   │   ├── hooks/
│   │   ├── services/
│   │   ├── store/
│   │   └── utils/
│   ├── dashboard/
│   ├── market-data/
│   ├── orders/
│   ├── positions/
│   ├── strategies/
│   ├── backtesting/
│   ├── reports/
│   ├── alerts/
│   ├── scheduler/
│   └── settings/
│
├── lib/                              # Core libraries & configs
│   ├── api/
│   │   ├── client.ts                 # Axios instance
│   │   ├── interceptors.ts
│   │   └── endpoints.ts
│   │
│   ├── websocket/
│   │   ├── client.ts                 # WebSocket client
│   │   ├── manager.ts                # Connection manager
│   │   └── handlers.ts
│   │
│   ├── utils/
│   │   ├── cn.ts                     # Classname utility
│   │   ├── formatters.ts
│   │   ├── validators.ts
│   │   └── constants.ts
│   │
│   └── config/
│       ├── env.ts
│       └── routes.ts
│
├── hooks/                            # Global custom hooks
│   ├── useDebounce.ts
│   ├── useLocalStorage.ts
│   ├── useMediaQuery.ts
│   ├── useKeyPress.ts
│   └── index.ts
│
├── stores/                           # Global state stores
│   ├── auth.store.ts
│   ├── market.store.ts
│   ├── positions.store.ts
│   ├── orders.store.ts
│   ├── ui.store.ts
│   └── index.ts
│
├── types/                            # TypeScript types
│   ├── api.types.ts
│   ├── trading.types.ts
│   ├── user.types.ts
│   ├── common.types.ts
│   └── index.ts
│
├── services/                         # Business logic services
│   ├── trading.service.ts
│   ├── market.service.ts
│   ├── order.service.ts
│   ├── position.service.ts
│   ├── strategy.service.ts
│   └── report.service.ts
│
├── utils/                            # Utility functions
│   ├── formatters/
│   │   ├── currency.ts
│   │   ├── number.ts
│   │   ├── date.ts
│   │   └── percentage.ts
│   │
│   ├── validators/
│   │   ├── order.validator.ts
│   │   ├── strategy.validator.ts
│   │   └── index.ts
│   │
│   ├── calculators/
│   │   ├── pnl.calculator.ts
│   │   ├── margin.calculator.ts
│   │   └── risk.calculator.ts
│   │
│   └── helpers/
│       ├── table.helpers.ts
│       ├── chart.helpers.ts
│       └── index.ts
│
├── constants/                        # App constants
│   ├── routes.ts
│   ├── api-endpoints.ts
│   ├── trading.ts
│   ├── colors.ts
│   └── index.ts
│
├── styles/                           # Global styles
│   ├── globals.css
│   ├── variables.css
│   ├── themes/
│   │   ├── dark.css
│   │   └── light.css
│   └── utilities.css
│
├── tests/                            # Test utilities
│   ├── mocks/
│   ├── fixtures/
│   ├── setup.ts
│   └── test-utils.tsx
│
├── public/                           # Static assets
│   ├── images/
│   ├── icons/
│   └── fonts/
│
├── next.config.js
├── tailwind.config.js
├── tsconfig.json
├── vitest.config.ts
└── playwright.config.ts
```

---

## 4. LAYOUT SYSTEM

### 4.1 Layout Hierarchy

```typescript
// app/layout.tsx - Root Layout
├── Providers (Theme, Query, Store)
└── AppLayout
    ├── Header (Top navigation)
    ├── Sidebar (Left navigation)
    └── Main Content
        └── Page-Specific Layout

// app/(dashboard)/layout.tsx - Dashboard Layout
├── AuthGuard
├── WebSocketProvider
└── DashboardLayout
    ├── MarketStatusHeader
    ├── NavigationSidebar
    └── ContentArea
```

### 4.2 Layout Components

#### 4.2.1 AppLayout Component

```typescript
// components/layout/AppLayout/AppLayout.tsx
interface AppLayoutProps {
  children: React.ReactNode;
  requireAuth?: boolean;
}

export const AppLayout: React.FC<AppLayoutProps> = ({
  children,
  requireAuth = true
}) => {
  const { sidebarCollapsed } = useUIStore();

  return (
    <div className="min-h-screen bg-gray-950 text-gray-100">
      <Header />
      <div className="flex">
        <Sidebar collapsed={sidebarCollapsed} />
        <main className={`flex-1 transition-all duration-300 ${
          sidebarCollapsed ? 'ml-16' : 'ml-64'
        }`}>
          <PageContainer>{children}</PageContainer>
        </main>
      </div>
      <Footer />
    </div>
  );
};
```

#### 4.2.2 Header Component

```typescript
// components/layout/Header/Header.tsx
export const Header: React.FC = () => {
  return (
    <header className="h-14 border-b border-gray-800 bg-gray-900/50 backdrop-blur fixed top-0 left-0 right-0 z-50">
      <div className="h-full px-4 flex items-center justify-between">
        {/* Left: Logo + Market Status */}
        <div className="flex items-center gap-4">
          <Logo />
          <MarketStatusBadge />
        </div>

        {/* Center: Search (optional) */}
        <div className="flex-1 max-w-md mx-4">
          <GlobalSearch />
        </div>

        {/* Right: Notifications + User */}
        <div className="flex items-center gap-3">
          <LiveIndicator />
          <TimeDisplay />
          <NotificationBell />
          <SettingsButton />
          <UserMenu />
        </div>
      </div>
    </header>
  );
};
```

#### 4.2.3 Sidebar Component

```typescript
// components/layout/Sidebar/Sidebar.tsx
interface SidebarProps {
  collapsed: boolean;
}

export const Sidebar: React.FC<SidebarProps> = ({ collapsed }) => {
  const navigation = useNavigation();

  return (
    <aside className={`fixed left-0 top-14 bottom-0 bg-gray-900 border-r border-gray-800 transition-all duration-300 z-40 ${
      collapsed ? 'w-16' : 'w-64'
    }`}>
      <nav className="p-2 space-y-1 overflow-y-auto h-[calc(100vh-3.5rem)]">
        {navigation.main.map((item) => (
          <SidebarItem key={item.id} item={item} collapsed={collapsed} />
        ))}

        <div className="pt-4 mt-4 border-t border-gray-800">
          {navigation.market.map((item) => (
            <SidebarItem key={item.id} item={item} collapsed={collapsed} />
          ))}
        </div>

        <div className="pt-4 mt-4 border-t border-gray-800">
          {navigation.portfolio.map((item) => (
            <SidebarItem key={item.id} item={item} collapsed={collapsed} />
          ))}
        </div>

        <div className="pt-4 mt-4 border-t border-gray-800">
          {navigation.system.map((item) => (
            <SidebarItem key={item.id} item={item} collapsed={collapsed} />
          ))}
        </div>
      </nav>

      {/* User Profile at Bottom */}
      <div className="absolute bottom-0 left-0 right-0 p-2 border-t border-gray-800">
        <UserProfileCard collapsed={collapsed} />
      </div>
    </aside>
  );
};
```

#### 4.2.4 PageContainer Component

```typescript
// components/layout/PageContainer/PageContainer.tsx
interface PageContainerProps {
  children: React.ReactNode;
  title?: string;
  subtitle?: string;
  actions?: React.ReactNode;
  padding?: 'none' | 'sm' | 'md' | 'lg';
}

export const PageContainer: React.FC<PageContainerProps> = ({
  children,
  title,
  subtitle,
  actions,
  padding = 'md'
}) => {
  const paddingClasses = {
    none: '',
    sm: 'p-4',
    md: 'p-6',
    lg: 'p-8'
  };

  return (
    <div className={`pt-14 min-h-screen ${paddingClasses[padding]}`}>
      {title && (
        <div className="mb-6 flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-100">{title}</h1>
            {subtitle && (
              <p className="text-sm text-gray-400 mt-1">{subtitle}</p>
            )}
          </div>
          {actions && <div className="flex gap-2">{actions}</div>}
        </div>
      )}
      {children}
    </div>
  );
};
```

### 4.3 Grid System

```typescript
// components/layout/Grid/Grid.tsx
interface GridProps {
  children: React.ReactNode;
  columns?: 1 | 2 | 3 | 4 | 6 | 12;
  gap?: 'sm' | 'md' | 'lg';
  className?: string;
}

export const Grid: React.FC<GridProps> = ({
  children,
  columns = 1,
  gap = 'md',
  className = ''
}) => {
  const gridCols = {
    1: 'grid-cols-1',
    2: 'grid-cols-1 md:grid-cols-2',
    3: 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3',
    4: 'grid-cols-1 md:grid-cols-2 lg:grid-cols-4',
    6: 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6',
    12: 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4'
  };

  const gaps = {
    sm: 'gap-3',
    md: 'gap-4',
    lg: 'gap-6'
  };

  return (
    <div className={`grid ${gridCols[columns]} ${gaps[gap]} ${className}`}>
      {children}
    </div>
  );
};

// Card Grid for KPIs
export const CardGrid: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <Grid columns={4} gap="md" className="mb-6">
    {children}
  </Grid>
);
```

---

## 5. COMPONENT ARCHITECTURE

### 5.1 Component Classification

Following **Atomic Design Methodology**:

#### Atoms (Basic Building Blocks)
- Button
- Input
- Select
- Badge
- Icon
- Avatar
- Checkbox
- Toggle
- Label

#### Molecules (Combinations of Atoms)
- SearchInput (Input + Button + Icon)
- FormField (Label + Input + Error)
- KPICard (Title + Value + Trend + Sparkline)
- StatusBadge (Icon + Badge)
- DropdownMenu (Button + Menu)

#### Organisms (Complex UI Components)
- DataTable (Header + Filters + Table + Pagination)
- ChartCard (Header + Chart + Legend)
- OrderBook (BidTable + AskTable + DepthBar)
- OptionChain (CallsTable + StrikeColumn + PutsTable)
- NavigationSidebar (Logo + MenuItems + UserProfile)

#### Templates (Page-level layouts)
- DashboardTemplate
- TableTemplate
- FormTemplate
- ChartTemplate

#### Pages (Full Pages)
- DashboardPage
- MarketWatchPage
- OptionChainPage
- PositionsPage
- OrdersPage

### 5.2 Component Patterns

#### Pattern 1: Compound Components

```typescript
// components/ui/Card/Card.tsx
interface CardProps {
  children: React.ReactNode;
  className?: string;
  variant?: 'default' | 'elevated' | 'outlined';
}

const Card: React.FC<CardProps> & {
  Header: typeof CardHeader;
  Content: typeof CardContent;
  Footer: typeof CardFooter;
} = ({ children, className, variant = 'default' }) => {
  const variants = {
    default: 'bg-gray-900 border border-gray-800',
    elevated: 'bg-gray-900 border border-gray-800 shadow-lg',
    outlined: 'border border-gray-700 bg-transparent'
  };

  return (
    <div className={`rounded-lg ${variants[variant]} ${className}`}>
      {children}
    </div>
  );
};

const CardHeader: React.FC<{ children: React.ReactNode; className?: string }> = ({
  children,
  className
}) => (
  <div className={`px-4 py-3 border-b border-gray-800 ${className}`}>
    {children}
  </div>
);

const CardContent: React.FC<{ children: React.ReactNode; className?: string }> = ({
  children,
  className
}) => (
  <div className={`p-4 ${className}`}>
    {children}
  </div>
);

const CardFooter: React.FC<{ children: React.ReactNode; className?: string }> = ({
  children,
  className
}) => (
  <div className={`px-4 py-3 border-t border-gray-800 ${className}`}>
    {children}
  </div>
);

Card.Header = CardHeader;
Card.Content = CardContent;
Card.Footer = CardFooter;

export { Card };

// Usage:
// <Card>
//   <Card.Header>
//     <h3>Net P&L</h3>
//   </Card.Header>
//   <Card.Content>
//     <KPICard value={24350} trend="+2.48%" />
//   </Card.Content>
// </Card>
```

#### Pattern 2: Render Props / Custom Hooks

```typescript
// hooks/useTable.ts
interface UseTableOptions<T> {
  data: T[];
  columns: ColumnDef<T>[];
  pagination?: {
    pageSize: number;
    initialPage?: number;
  };
  sorting?: boolean;
  filtering?: boolean;
}

export const useTable = <T,>({
  data,
  columns,
  pagination,
  sorting = true,
  filtering = true
}: UseTableOptions<T>) => {
  const [paginationState, setPaginationState] = useState({
    pageIndex: pagination?.initialPage || 0,
    pageSize: pagination?.pageSize || 10
  });

  const table = useReactTable({
    data,
    columns,
    state: {
      pagination: paginationState
    },
    onPaginationChange: setPaginationState,
    getCoreRowModel: getCoreRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    ...(sorting && { getSortedRowModel: getSortedRowModel() }),
    ...(filtering && { getFilteredRowModel: getFilteredRowModel() })
  });

  return {
    table,
    rows: table.getRowModel().rows,
    pagination: {
      currentPage: paginationState.pageIndex,
      pageSize: paginationState.pageSize,
      totalPages: table.getPageCount(),
      totalRows: data.length,
      onPageChange: table.setPageIndex,
      onPageSizeChange: table.setPageSize
    }
  };
};

// Usage in component:
const OrdersTable: React.FC = () => {
  const { data: orders } = useOrders();
  const columns = useOrderColumns();

  const { table, rows, pagination } = useTable({
    data: orders,
    columns,
    pagination: { pageSize: 10 }
  });

  return (
    <Table>
      <Table.Header>
        {table.getHeaderGroups().map(headerGroup => (
          <Table.Row key={headerGroup.id}>
            {headerGroup.headers.map(header => (
              <Table.Head key={header.id}>
                <flexRender
                  header.column.columnDef.header
                  header.getContext()
                />
              </Table.Head>
            ))}
          </Table.Row>
        ))}
      </Table.Header>
      <Table.Body>
        {rows.map(row => (
          <Table.Row key={row.id}>
            {row.getVisibleCells().map(cell => (
              <Table.Cell key={cell.id}>
                <flexRender
                  cell.column.columnDef.cell
                  cell.getContext()
                />
              </Table.Cell>
            ))}
          </Table.Row>
        ))}
      </Table.Body>
    </Table>
  );
};
```

#### Pattern 3: Slot Pattern for Extensibility

```typescript
// components/trading/KPICard/KPICard.tsx
interface KPICardProps {
  title: string;
  value: string | number;
  trend?: {
    value: number;
    type: 'positive' | 'negative' | 'neutral';
  };
  sparkline?: number[];
  icon?: React.ReactNode;
  action?: React.ReactNode; // Slot for custom actions
  footer?: React.ReactNode; // Slot for custom footer
  className?: string;
}

export const KPICard: React.FC<KPICardProps> = ({
  title,
  value,
  trend,
  sparkline,
  icon,
  action,
  footer,
  className
}) => {
  return (
    <Card className={className}>
      <Card.Header>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {icon && <span className="text-gray-400">{icon}</span>}
            <span className="text-sm font-medium text-gray-400">{title}</span>
          </div>
          {action && <div>{action}</div>}
        </div>
      </Card.Header>
      <Card.Content>
        <div className="flex items-end justify-between">
          <div>
            <div className="text-2xl font-bold text-gray-100">
              {formatValue(value)}
            </div>
            {trend && (
              <TrendBadge
                value={trend.value}
                type={trend.type}
              />
            )}
          </div>
          {sparkline && (
            <SparklineChart data={sparkline} />
          )}
        </div>
      </Card.Content>
      {footer && (
        <Card.Footer className="text-xs text-gray-500">
          {footer}
        </Card.Footer>
      )}
    </Card>
  );
};
```

---

## 6. REUSABLE UI COMPONENTS

### 6.1 Core UI Components

#### Button Component

```typescript
// components/ui/Button/Button.tsx
import { cva, type VariantProps } from 'class-variance-authority';

const buttonVariants = cva(
  'inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none',
  {
    variants: {
      variant: {
        default: 'bg-green-600 text-white hover:bg-green-700',
        destructive: 'bg-red-600 text-white hover:bg-red-700',
        outline: 'border border-gray-700 hover:bg-gray-800',
        secondary: 'bg-gray-800 text-gray-100 hover:bg-gray-700',
        ghost: 'hover:bg-gray-800',
        link: 'underline-offset-4 hover:underline text-green-500',
      },
      size: {
        default: 'h-10 py-2 px-4',
        sm: 'h-9 px-3',
        lg: 'h-11 px-8',
        icon: 'h-10 w-10',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
  loading?: boolean;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, loading, leftIcon, rightIcon, children, ...props }, ref) => {
    return (
      <button
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        disabled={loading || props.disabled}
        {...props}
      >
        {loading && <LoadingSpinner className="mr-2 h-4 w-4 animate-spin" />}
        {!loading && leftIcon && <span className="mr-2">{leftIcon}</span>}
        {children}
        {!loading && rightIcon && <span className="ml-2">{rightIcon}</span>}
      </button>
    );
  }
);
Button.displayName = 'Button';

export { Button, buttonVariants };
```

#### Badge Component

```typescript
// components/ui/Badge/Badge.tsx
import { cva, type VariantProps } from 'class-variance-authority';

const badgeVariants = cva(
  'inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2',
  {
    variants: {
      variant: {
        default: 'border-transparent bg-gray-800 text-gray-100',
        secondary: 'border-transparent bg-gray-700 text-gray-200',
        success: 'border-transparent bg-green-900/50 text-green-400',
        danger: 'border-transparent bg-red-900/50 text-red-400',
        warning: 'border-transparent bg-yellow-900/50 text-yellow-400',
        info: 'border-transparent bg-blue-900/50 text-blue-400',
        outline: 'border-gray-700 text-gray-400',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {
  dot?: boolean;
  dotColor?: 'green' | 'red' | 'yellow' | 'blue';
}

function Badge({ className, variant, dot, dotColor = 'green', ...props }: BadgeProps) {
  return (
    <div className={cn(badgeVariants({ variant }), className)} {...props}>
      {dot && (
        <span
          className={cn(
            'mr-1.5 h-1.5 w-1.5 rounded-full',
            dotColor === 'green' && 'bg-green-400',
            dotColor === 'red' && 'bg-red-400',
            dotColor === 'yellow' && 'bg-yellow-400',
            dotColor === 'blue' && 'bg-blue-400'
          )}
        />
      )}
      {props.children}
    </div>
  );
}

export { Badge, badgeVariants };
```

#### Table Component

```typescript
// components/ui/Table/Table.tsx
const Table = React.forwardRef<
  HTMLTableElement,
  React.HTMLAttributes<HTMLTableElement>
>(({ className, ...props }, ref) => (
  <div className="relative w-full overflow-auto">
    <table
      ref={ref}
      className={cn('w-full caption-bottom text-sm', className)}
      {...props}
    />
  </div>
));
Table.displayName = 'Table';

const TableHeader = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
  <thead ref={ref} className={cn('[&_tr]:border-b', className)} {...props} />
));
TableHeader.displayName = 'TableHeader';

const TableBody = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
  <tbody
    ref={ref}
    className={cn('[&_tr:last-child]:border-0', className)}
    {...props}
  />
));
TableBody.displayName = 'TableBody';

const TableRow = React.forwardRef<
  HTMLTableRowElement,
  React.HTMLAttributes<HTMLTableRowElement> & { clickable?: boolean }
>(({ className, clickable, ...props }, ref) => (
  <tr
    ref={ref}
    className={cn(
      'border-b transition-colors',
      clickable && 'cursor-pointer hover:bg-gray-800/50',
      className
    )}
    {...props}
  />
));
TableRow.displayName = 'TableRow';

const TableHead = React.forwardRef<
  HTMLTableCellElement,
  React.ThHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
  <th
    ref={ref}
    className={cn(
      'h-12 px-4 text-left align-middle font-medium text-gray-400 [&:has([role=checkbox])]:pr-0',
      className
    )}
    {...props}
  />
));
TableHead.displayName = 'TableHead';

const TableCell = React.forwardRef<
  HTMLTableCellElement,
  React.TdHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
  <td
    ref={ref}
    className={cn('p-4 align-middle [&:has([role=checkbox])]:pr-0', className)}
    {...props}
  />
));
TableCell.displayName = 'TableCell';

export {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
};
```

#### Modal/Dialog Component

```typescript
// components/ui/Modal/Modal.tsx
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';

const Modal = DialogPrimitive.Root;
const ModalTrigger = DialogPrimitive.Trigger;
const ModalPortal = DialogPrimitive.Portal;
const ModalClose = DialogPrimitive.Close;

const ModalOverlay = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Overlay>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Overlay
    ref={ref}
    className={cn(
      'fixed inset-0 z-50 bg-black/80 backdrop-blur-sm data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0',
      className
    )}
    {...props}
  />
));
ModalOverlay.displayName = DialogPrimitive.Overlay.displayName;

const ModalContent = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Content>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content> & {
    size?: 'sm' | 'md' | 'lg' | 'xl' | 'full';
  }
>(({ className, children, size = 'md', ...props }, ref) => {
  const sizes = {
    sm: 'max-w-md',
    md: 'max-w-2xl',
    lg: 'max-w-4xl',
    xl: 'max-w-6xl',
    full: 'max-w-[95vw] w-full',
  };

  return (
    <ModalPortal>
      <ModalOverlay />
      <DialogPrimitive.Content
        ref={ref}
        className={cn(
          'fixed left-[50%] top-[50%] z-50 translate-x-[-50%] translate-y-[-50%] border border-gray-800 bg-gray-900 shadow-lg duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-to-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%] rounded-lg',
          sizes[size],
          className
        )}
        {...props}
      >
        {children}
        <DialogPrimitive.Close className="absolute right-4 top-4 rounded-sm opacity-70 ring-offset-background transition-opacity hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:pointer-events-none data-[state=open]:bg-accent data-[state=open]:text-muted-foreground">
          <X className="h-4 w-4" />
          <span className="sr-only">Close</span>
        </DialogPrimitive.Close>
      </DialogPrimitive.Content>
    </ModalPortal>
  );
});
ModalContent.displayName = DialogPrimitive.Content.displayName;

const ModalHeader = ({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) => (
  <div
    className={cn(
      'flex flex-col space-y-1.5 p-6 border-b border-gray-800',
      className
    )}
    {...props}
  />
);
ModalHeader.displayName = 'ModalHeader';

const ModalFooter = ({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) => (
  <div
    className={cn(
      'flex flex-row-reverse space-x-2 space-x-reverse p-6 border-t border-gray-800',
      className
    )}
    {...props}
  />
);
ModalFooter.displayName = 'ModalFooter';

export {
  Modal,
  ModalTrigger,
  ModalContent,
  ModalHeader,
  ModalFooter,
  ModalClose,
};
```

### 6.2 Form Components

#### Input Component

```typescript
// components/ui/Input/Input.tsx
export interface InputProps
  extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  helperText?: string;
  leftAddon?: React.ReactNode;
  rightAddon?: React.ReactNode;
}

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, label, error, helperText, leftAddon, rightAddon, ...props }, ref) => {
    return (
      <div className="w-full">
        {label && (
          <label className="block text-sm font-medium text-gray-300 mb-1.5">
            {label}
          </label>
        )}
        <div className="relative">
          {leftAddon && (
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              {leftAddon}
            </div>
          )}
          <input
            ref={ref}
            className={cn(
              'flex h-10 w-full rounded-md border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-gray-100 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-green-500 focus:border-transparent disabled:cursor-not-allowed disabled:opacity-50',
              leftAddon && 'pl-10',
              rightAddon && 'pr-10',
              error && 'border-red-500 focus:ring-red-500',
              className
            )}
            {...props}
          />
          {rightAddon && (
            <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
              {rightAddon}
            </div>
          )}
        </div>
        {error && (
          <p className="mt-1.5 text-sm text-red-400">{error}</p>
        )}
        {helperText && !error && (
          <p className="mt-1.5 text-sm text-gray-500">{helperText}</p>
        )}
      </div>
    );
  }
);
Input.displayName = 'Input';

export { Input };
```

#### Select Component

```typescript
// components/ui/Select/Select.tsx
import * as SelectPrimitive from '@radix-ui/react-select';
import { Check, ChevronDown } from 'lucide-react';

const Select = SelectPrimitive.Root;
const SelectGroup = SelectPrimitive.Group;
const SelectValue = SelectPrimitive.Value;

const SelectTrigger = React.forwardRef<
  React.ElementRef<typeof SelectPrimitive.Trigger>,
  React.ComponentPropsWithoutRef<typeof SelectPrimitive.Trigger> & {
    label?: string;
    error?: string;
  }
>(({ className, children, label, error, ...props }, ref) => (
  <div className="w-full">
    {label && (
      <label className="block text-sm font-medium text-gray-300 mb-1.5">
        {label}
      </label>
    )}
    <SelectPrimitive.Trigger
      ref={ref}
      className={cn(
        'flex h-10 w-full items-center justify-between rounded-md border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-gray-100 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-green-500 focus:border-transparent disabled:cursor-not-allowed disabled:opacity-50',
        error && 'border-red-500 focus:ring-red-500',
        className
      )}
      {...props}
    >
      {children}
      <SelectPrimitive.Icon asChild>
        <ChevronDown className="h-4 w-4 opacity-50" />
      </SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
    {error && (
      <p className="mt-1.5 text-sm text-red-400">{error}</p>
    )}
  </div>
));
SelectTrigger.displayName = SelectPrimitive.Trigger.displayName;

const SelectContent = React.forwardRef<
  React.ElementRef<typeof SelectPrimitive.Content>,
  React.ComponentPropsWithoutRef<typeof SelectPrimitive.Content>
>(({ className, children, position = 'popper', ...props }, ref) => (
  <SelectPrimitive.Portal>
    <SelectPrimitive.Content
      ref={ref}
      className={cn(
        'relative z-50 min-w-[8rem] overflow-hidden rounded-md border border-gray-800 bg-gray-900 text-gray-100 shadow-md data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95',
        position === 'popper' &&
          'data-[side=bottom]:translate-y-1 data-[side=left]:-translate-x-1 data-[side=right]:translate-x-1 data-[side=top]:-translate-y-1',
        className
      )}
      position={position}
      {...props}
    >
      <SelectPrimitive.Viewport
        className={cn(
          'p-1',
          position === 'popper' &&
            'h-[var(--radix-select-trigger-height)] w-full min-w-[var(--radix-select-trigger-width)]'
        )}
      >
        {children}
      </SelectPrimitive.Viewport>
    </SelectPrimitive.Content>
  </SelectPrimitive.Portal>
));
SelectContent.displayName = SelectPrimitive.Content.displayName;

const SelectItem = React.forwardRef<
  React.ElementRef<typeof SelectPrimitive.Item>,
  React.ComponentPropsWithoutRef<typeof SelectPrimitive.Item>
>(({ className, children, ...props }, ref) => (
  <SelectPrimitive.Item
    ref={ref}
    className={cn(
      'relative flex w-full cursor-default select-none items-center rounded-sm py-1.5 pl-8 pr-2 text-sm outline-none focus:bg-gray-800 focus:text-gray-100 data-[disabled]:pointer-events-none data-[disabled]:opacity-50',
      className
    )}
    {...props}
  >
    <span className="absolute left-2 flex h-3.5 w-3.5 items-center justify-center">
      <SelectPrimitive.ItemIndicator>
        <Check className="h-4 w-4 text-green-500" />
      </SelectPrimitive.ItemIndicator>
    </span>
    <SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
  </SelectPrimitive.Item>
));
SelectItem.displayName = SelectPrimitive.Item.displayName;

export {
  Select,
  SelectGroup,
  SelectValue,
  SelectTrigger,
  SelectContent,
  SelectItem,
};
```

### 6.3 Feedback Components

#### Toast/Notification System

```typescript
// components/ui/Toast/Toast.tsx
import * as ToastPrimitives from '@radix-ui/react-toast';
import { cva, type VariantProps } from 'class-variance-authority';
import { X } from 'lucide-react';

const ToastProvider = ToastPrimitives.Provider;

const ToastViewport = React.forwardRef<
  React.ElementRef<typeof ToastPrimitives.Viewport>,
  React.ComponentPropsWithoutRef<typeof ToastPrimitives.Viewport>
>(({ className, ...props }, ref) => (
  <ToastPrimitives.Viewport
    ref={ref}
    className={cn(
      'fixed top-0 z-[100] flex max-h-screen w-full flex-col-reverse p-4 sm:bottom-0 sm:right-0 sm:top-auto sm:flex-col md:max-w-[420px]',
      className
    )}
    {...props}
  />
));
ToastViewport.displayName = ToastPrimitives.Viewport.displayName;

const toastVariants = cva(
  'group pointer-events-auto relative flex w-full items-center justify-between space-x-4 overflow-hidden rounded-md border border-gray-800 p-6 pr-8 shadow-lg transition-all data-[swipe=cancel]:translate-x-0 data-[swipe=end]:translate-x-[var(--radix-toast-swipe-end-x)] data-[swipe=move]:translate-x-[var(--radix-toast-swipe-move-x)] data-[swipe=move]:transition-none data-[state=open]:animate-in data-[state=closed]:animate-out data-[swipe=end]:animate-out data-[state=closed]:fade-out-80 data-[state=closed]:slide-out-to-right-full data-[state=open]:slide-in-from-top-full data-[state=open]:sm:slide-in-from-bottom-full',
  {
    variants: {
      variant: {
        default: 'border bg-gray-900 text-gray-100',
        success: 'success group border-green-900/50 bg-green-950 text-green-100',
        error: 'error group border-red-900/50 bg-red-950 text-red-100',
        warning: 'warning group border-yellow-900/50 bg-yellow-950 text-yellow-100',
        info: 'info group border-blue-900/50 bg-blue-950 text-blue-100',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
);

const Toast = React.forwardRef<
  React.ElementRef<typeof ToastPrimitives.Root>,
  React.ComponentPropsWithoutRef<typeof ToastPrimitives.Root> &
    VariantProps<typeof toastVariants>
>(({ className, variant, ...props }, ref) => {
  return (
    <ToastPrimitives.Root
      ref={ref}
      className={cn(toastVariants({ variant }), className)}
      {...props}
    />
  );
});
Toast.displayName = ToastPrimitives.Root.displayName;

const ToastAction = React.forwardRef<
  React.ElementRef<typeof ToastPrimitives.Action>,
  React.ComponentPropsWithoutRef<typeof ToastPrimitives.Action>
>(({ className, ...props }, ref) => (
  <ToastPrimitives.Action
    ref={ref}
    className={cn(
      'inline-flex h-8 shrink-0 items-center justify-center rounded-md border border-gray-700 bg-transparent px-3 text-sm font-medium ring-offset-background transition-colors hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:pointer-events-none disabled:opacity-50',
      className
    )}
    {...props}
  />
));
ToastAction.displayName = ToastPrimitives.Action.displayName;

const ToastClose = React.forwardRef<
  React.ElementRef<typeof ToastPrimitives.Close>,
  React.ComponentPropsWithoutRef<typeof ToastPrimitives.Close>
>(({ className, ...props }, ref) => (
  <ToastPrimitives.Close
    ref={ref}
    className={cn(
      'absolute right-2 top-2 rounded-md p-1 text-gray-400 opacity-0 transition-opacity hover:text-gray-100 focus:opacity-100 focus:outline-none focus:ring-2 group-hover:opacity-100',
      className
    )}
    toast-close=""
    {...props}
  >
    <X className="h-4 w-4" />
  </ToastPrimitives.Close>
));
ToastClose.displayName = ToastPrimitives.Close.displayName;

const ToastTitle = React.forwardRef<
  React.ElementRef<typeof ToastPrimitives.Title>,
  React.ComponentPropsWithoutRef<typeof ToastPrimitives.Title>
>(({ className, ...props }, ref) => (
  <ToastPrimitives.Title
    ref={ref}
    className={cn('text-sm font-semibold', className)}
    {...props}
  />
));
ToastTitle.displayName = ToastPrimitives.Title.displayName;

const ToastDescription = React.forwardRef<
  React.ElementRef<typeof ToastPrimitives.Description>,
  React.ComponentPropsWithoutRef<typeof ToastPrimitives.Description>
>(({ className, ...props }, ref) => (
  <ToastPrimitives.Description
    ref={ref}
    className={cn('text-sm opacity-90', className)}
    {...props}
  />
));
ToastDescription.displayName = ToastPrimitives.Description.displayName;

type ToastProps = React.ComponentPropsWithoutRef<typeof Toast>;
type ToastActionElement = React.ReactElement<typeof ToastAction>;

export {
  ToastProvider,
  ToastViewport,
  Toast,
  ToastTitle,
  ToastDescription,
  ToastClose,
  ToastAction,
  type ToastProps,
  type ToastActionElement,
};

// Toast Hook for easy usage
// hooks/useToast.ts
export interface ToastOptions {
  title?: string;
  description?: string;
  action?: ToastActionElement;
  duration?: number;
}

export const useToast = () => {
  const [toasts, setToasts] = useState<Array<ToastProps & { id: string }>>([]);

  const toast = useCallback(
    ({ title, description, action, duration = 5000, ...props }: ToastOptions) => {
      const id = Math.random().toString(36).substr(2, 9);

      setToasts((prev) => [
        ...prev,
        { id, title, description, action, ...props },
      ]);

      if (duration) {
        setTimeout(() => {
          setToasts((prev) => prev.filter((t) => t.id !== id));
        }, duration);
      }

      return id;
    },
    []
  );

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return {
    toasts,
    toast,
    dismiss,
    success: (options: Omit<ToastOptions, 'variant'>) =>
      toast({ ...options, variant: 'success' }),
    error: (options: Omit<ToastOptions, 'variant'>) =>
      toast({ ...options, variant: 'error' }),
    warning: (options: Omit<ToastOptions, 'variant'>) =>
      toast({ ...options, variant: 'warning' }),
    info: (options: Omit<ToastOptions, 'variant'>) =>
      toast({ ...options, variant: 'info' }),
  };
};
```

---

## 7. DOMAIN-SPECIFIC COMPONENTS

### 7.1 Trading Components

#### KPICard Component

```typescript
// components/trading/KPICard/KPICard.tsx
interface KPICardProps {
  title: string;
  value: string | number;
  formattedValue?: string;
  trend?: {
    value: number;
    formattedValue?: string;
    type?: 'positive' | 'negative' | 'neutral';
  };
  sparkline?: number[];
  icon?: React.ReactNode;
  tooltip?: string;
  loading?: boolean;
  className?: string;
}

export const KPICard: React.FC<KPICardProps> = ({
  title,
  value,
  formattedValue,
  trend,
  sparkline,
  icon,
  tooltip,
  loading = false,
  className
}) => {
  const trendType = trend?.type || (trend && trend.value >= 0 ? 'positive' : 'negative');

  return (
    <Card className={cn('relative overflow-hidden', className)}>
      <Card.Header>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {icon && <span className="text-gray-400">{icon}</span>}
            <span className="text-sm font-medium text-gray-400">{title}</span>
            {tooltip && (
              <Tooltip content={tooltip}>
                <Info className="h-4 w-4 text-gray-500" />
              </Tooltip>
            )}
          </div>
        </div>
      </Card.Header>
      <Card.Content>
        {loading ? (
          <Skeleton className="h-8 w-32" />
        ) : (
          <div className="flex items-end justify-between">
            <div>
              <div className="text-2xl font-bold text-gray-100">
                {formattedValue || formatCurrency(value)}
              </div>
              {trend && (
                <div className="mt-1">
                  <TrendBadge
                    value={trend.formattedValue || trend.value}
                    type={trendType}
                    showIcon
                  />
                </div>
              )}
            </div>
            {sparkline && sparkline.length > 0 && (
              <div className="h-12 w-24">
                <SparklineChart
                  data={sparkline}
                  trend={trendType}
                />
              </div>
            )}
          </div>
        )}
      </Card.Content>
    </Card>
  );
};

// components/trading/TrendBadge/TrendBadge.tsx
interface TrendBadgeProps {
  value: number | string;
  type: 'positive' | 'negative' | 'neutral';
  showIcon?: boolean;
  className?: string;
}

export const TrendBadge: React.FC<TrendBadgeProps> = ({
  value,
  type,
  showIcon = false,
  className
}) => {
  const colors = {
    positive: 'text-green-400',
    negative: 'text-red-400',
    neutral: 'text-gray-400'
  };

  const icons = {
    positive: TrendingUp,
    negative: TrendingDown,
    neutral: Minus
  };

  const Icon = icons[type];

  return (
    <span className={cn('text-sm font-medium', colors[type], className)}>
      {showIcon && <Icon className="inline h-3 w-3 mr-1" />}
      {typeof value === 'number' ? formatPercentage(value) : value}
    </span>
  );
};
```

#### CandlestickChart Component

```typescript
// components/charts/CandlestickChart/CandlestickChart.tsx
import { createChart, IChartApi, ISeriesApi, CandlestickData } from 'lightweight-charts';

interface CandlestickChartProps {
  data: CandlestickData[];
  volume?: { time: number; value: number }[];
  indicators?: {
    sma?: { period: number; data: number[] }[];
    ema?: { period: number; data: number[] }[];
  };
  trades?: TradeMarker[];
  height?: number;
  className?: string;
}

interface TradeMarker {
  time: number;
  price: number;
  type: 'BUY' | 'SELL';
  label?: string;
}

export const CandlestickChart: React.FC<CandlestickChartProps> = ({
  data,
  volume,
  indicators,
  trades,
  height = 400,
  className
}) => {
  const chartContainerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const candleSeriesRef = useRef<ISeriesApi<'Candlestick'> | null>(null);

  useEffect(() => {
    if (!chartContainerRef.current) return;

    // Create chart
    const chart = createChart(chartContainerRef.current, {
      width: chartContainerRef.current.clientWidth,
      height,
      layout: {
        background: { type: 'solid', color: '#0B1120' },
        textColor: '#94A3B8',
      },
      grid: {
        vertLines: { color: '#1E293B' },
        horzLines: { color: '#1E293B' },
      },
      crosshair: {
        mode: CrosshairMode.Normal,
      },
      rightPriceScale: {
        borderColor: '#334155',
      },
      timeScale: {
        borderColor: '#334155',
        timeVisible: true,
        secondsVisible: false,
      },
    });

    chartRef.current = chart;

    // Add candlestick series
    const candleSeries = chart.addCandlestickSeries({
      upColor: '#22C55E',
      downColor: '#EF4444',
      borderDownColor: '#EF4444',
      borderUpColor: '#22C55E',
      wickDownColor: '#EF4444',
      wickUpColor: '#22C55E',
    });

    candleSeriesRef.current = candleSeries;
    candleSeries.setData(data);

    // Add volume if provided
    if (volume && volume.length > 0) {
      const volumeSeries = chart.addHistogramSeries({
        color: '#22C55E',
        priceFormat: {
          type: 'volume',
        },
        priceScaleId: '',
        scaleMargins: {
          top: 0.8,
          bottom: 0,
        },
      });

      volumeSeries.setData(
        volume.map(v => ({
          time: v.time as any,
          value: v.value,
          color: v.value > 0 ? '#22C55E80' : '#EF444480',
        }))
      );
    }

    // Add trade markers
    if (trades && trades.length > 0) {
      const markers = trades.map(trade => ({
        time: trade.time as any,
        position: trade.type === 'BUY' ? 'belowBar' : 'aboveBar',
        color: trade.type === 'BUY' ? '#22C55E' : '#EF4444',
        shape: trade.type === 'BUY' ? 'arrowUp' : 'arrowDown',
        text: trade.label || trade.type,
      }));

      candleSeries.setMarkers(markers);
    }

    // Handle resize
    const handleResize = () => {
      if (chartContainerRef.current && chartRef.current) {
        chartRef.current.applyOptions({
          width: chartContainerRef.current.clientWidth,
        });
      }
    };

    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      chart.remove();
    };
  }, [data, volume, trades, height]);

  // Update data when it changes
  useEffect(() => {
    if (candleSeriesRef.current && data.length > 0) {
      candleSeriesRef.current.setData(data);
    }
  }, [data]);

  return (
    <div className={cn('relative', className)}>
      <div ref={chartContainerRef} style={{ height }} />
    </div>
  );
};
```

#### OptionChain Component

```typescript
// components/trading/OptionChain/OptionChain.tsx
interface OptionChainProps {
  underlying: string;
  spotPrice: number;
  expiry: string;
  strikes: StrikeData[];
  view: 'LTP' | 'OI' | 'Greeks';
  onStrikeClick?: (strike: number, type: 'CE' | 'PE') => void;
  loading?: boolean;
}

interface StrikeData {
  strike: number;
  call: {
    ltp: number;
    oi: number;
    changeInOI: number;
    volume: number;
    iv: number;
    delta: number;
    gamma: number;
    theta: number;
    vega: number;
  };
  put: {
    ltp: number;
    oi: number;
    changeInOI: number;
    volume: number;
    iv: number;
    delta: number;
    gamma: number;
    theta: number;
    vega: number;
  };
}

export const OptionChain: React.FC<OptionChainProps> = ({
  underlying,
  spotPrice,
  expiry,
  strikes,
  view,
  onStrikeClick,
  loading = false
}) => {
  const atmStrike = findATMStrike(strikes.map(s => s.strike), spotPrice);

  const columns = useMemo(() => [
    { key: 'callOi', label: 'OI', align: 'right' },
    { key: 'callChangeOi', label: 'Chg in OI', align: 'right' },
    { key: 'callVolume', label: 'Volume', align: 'right' },
    { key: 'callLtp', label: 'LTP', align: 'right' },
    { key: 'callChg', label: 'Chg %', align: 'right' },
    ...(view === 'Greeks' ? [
      { key: 'callIv', label: 'IV', align: 'right' },
      { key: 'callDelta', label: 'Delta', align: 'right' },
      { key: 'callGamma', label: 'Gamma', align: 'right' },
      { key: 'callTheta', label: 'Theta', align: 'right' },
      { key: 'callVega', label: 'Vega', align: 'right' },
    ] : []),
  ], [view]);

  return (
    <div className="border border-gray-800 rounded-lg overflow-hidden">
      {/* Header */}
      <div className="bg-gray-900 px-4 py-3 border-b border-gray-800">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <h3 className="text-lg font-semibold">{underlying}</h3>
            <div className="flex items-center gap-2">
              <span className="text-2xl font-bold text-gray-100">
                {formatPrice(spotPrice)}
              </span>
              <Badge variant="success">Spot</Badge>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-sm text-gray-400">Expiry:</span>
            <Select value={expiry} onValueChange={() => {}}>
              <SelectTrigger className="w-40">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="06 JUN 2024">06 JUN 2024 (Weekly)</SelectItem>
                <SelectItem value="13 JUN 2024">13 JUN 2024 (Weekly)</SelectItem>
                <SelectItem value="27 JUN 2024">27 JUN 2024 (Monthly)</SelectItem>
              </SelectContent>
            </Select>

            <Tabs value={view} onValueChange={() => {}}>
              <TabsList>
                <TabsTrigger value="LTP">LTP</TabsTrigger>
                <TabsTrigger value="OI">OI</TabsTrigger>
                <TabsTrigger value="Greeks">Greeks</TabsTrigger>
              </TabsList>
            </Tabs>
          </div>
        </div>
      </div>

      {/* Option Chain Table */}
      <div className="overflow-auto max-h-[600px]">
        <table className="w-full text-sm">
          <thead className="sticky top-0 bg-gray-900 border-b border-gray-800">
            <tr>
              {/* Call Headers */}
              {columns.map(col => (
                <th key={`call-${col.key}`} className="px-3 py-2 text-right text-gray-400 font-medium">
                  {col.label}
                </th>
              ))}

              {/* Strike Column */}
              <th className="px-4 py-2 text-center text-gray-300 font-semibold bg-gray-800/50">
                Strike
              </th>

              {/* Put Headers (mirror of call) */}
              {columns.map(col => (
                <th key={`put-${col.key}`} className="px-3 py-2 text-right text-gray-400 font-medium">
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              // Loading skeletons
              Array.from({ length: 10 }).map((_, i) => (
                <tr key={i} className="border-b border-gray-800/50">
                  <td colSpan={columns.length * 2 + 1} className="px-4 py-3">
                    <Skeleton className="h-6 w-full" />
                  </td>
                </tr>
              ))
            ) : (
              strikes.map((strikeData) => {
                const isATM = strikeData.strike === atmStrike;

                return (
                  <tr
                    key={strikeData.strike}
                    className={cn(
                      'border-b border-gray-800/50 hover:bg-gray-800/30',
                      isATM && 'bg-blue-900/20'
                    )}
                  >
                    {/* Call Data */}
                    {columns.map(col => (
                      <td key={`call-${col.key}`} className="px-3 py-2 text-right">
                        <OptionChainCell
                          value={getOptionValue(strikeData.call, col.key)}
                          type="call"
                          onClick={() => onStrikeClick?.(strikeData.strike, 'CE')}
                        />
                      </td>
                    ))}

                    {/* Strike */}
                    <td className={cn(
                      'px-4 py-2 text-center font-semibold',
                      isATM ? 'text-blue-400 bg-blue-900/20' : 'text-gray-200'
                    )}>
                      {strikeData.strike}
                    </td>

                    {/* Put Data */}
                    {columns.map(col => (
                      <td key={`put-${col.key}`} className="px-3 py-2 text-right">
                        <OptionChainCell
                          value={getOptionValue(strikeData.put, col.key)}
                          type="put"
                          onClick={() => onStrikeClick?.(strikeData.strike, 'PE')}
                        />
                      </td>
                    ))}
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};

// Helper component for option chain cells
const OptionChainCell: React.FC<{
  value: number;
  type: 'call' | 'put';
  onClick?: () => void;
}> = ({ value, type, onClick }) => {
  const isPositive = value > 0;
  const isNegative = value < 0;

  let textColor = 'text-gray-300';
  if (isPositive) textColor = 'text-green-400';
  if (isNegative) textColor = 'text-red-400';

  return (
    <button
      onClick={onClick}
      className={cn(
        'w-full text-right hover:underline',
        textColor
      )}
    >
      {formatValue(value)}
    </button>
  );
};
```

#### DataTable Component (Generic)

```typescript
// components/ui/DataTable/DataTable.tsx
import {
  useReactTable,
  getCoreRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  getFilteredRowModel,
  flexRender,
  ColumnDef,
  SortingState,
  PaginationState,
} from '@tanstack/react-table';

interface DataTableProps<TData, TValue> {
  columns: ColumnDef<TData, TValue>[];
  data: TData[];
  pagination?: {
    pageSize?: number;
    pageIndex?: number;
    totalRows?: number;
    onPageChange?: (page: number) => void;
    onPageSizeChange?: (size: number) => void;
  };
  sorting?: {
    initialSorting?: SortingState;
    onSortingChange?: (sorting: SortingState) => void;
  };
  filtering?: {
    globalFilter?: string;
    onGlobalFilterChange?: (filter: string) => void;
  };
  rowSelection?: {
    selectedRowIds?: string[];
    onRowSelectionChange?: (ids: string[]) => void;
  };
  actions?: React.ReactNode;
  className?: string;
}

export function DataTable<TData, TValue>({
  columns,
  data,
  pagination,
  sorting,
  filtering,
  rowSelection,
  actions,
  className
}: DataTableProps<TData, TValue>) {
  const [sortingState, setSortingState] = useState<SortingState>(
    sorting?.initialSorting || []
  );
  const [paginationState, setPaginationState] = useState<PaginationState>({
    pageIndex: pagination?.pageIndex || 0,
    pageSize: pagination?.pageSize || 10,
  });
  const [globalFilter, setGlobalFilter] = useState(filtering?.globalFilter || '');
  const [rowSelectionState, setRowSelectionState] = useState<Record<string, boolean>>({});

  const table = useReactTable({
    data,
    columns,
    state: {
      sorting: sortingState,
      pagination: paginationState,
      globalFilter,
      rowSelection: rowSelectionState,
    },
    onSortingChange: (updater) => {
      const newSorting = typeof updater === 'function'
        ? updater(sortingState)
        : updater;
      setSortingState(newSorting);
      sorting?.onSortingChange?.(newSorting);
    },
    onPaginationChange: (updater) => {
      const newPagination = typeof updater === 'function'
        ? updater(paginationState)
        : updater;
      setPaginationState(newPagination);
      pagination?.onPageChange?.(newPagination.pageIndex);
      pagination?.onPageSizeChange?.(newPagination.pageSize);
    },
    onGlobalFilterChange: (filter) => {
      setGlobalFilter(filter);
      filtering?.onGlobalFilterChange?.(filter);
    },
    onRowSelectionChange: (updater) => {
      const newSelection = typeof updater === 'function'
        ? updater(rowSelectionState)
        : updater;
      setRowSelectionState(newSelection);
      rowSelection?.onRowSelectionChange?.(
        Object.keys(newSelection).filter(key => newSelection[key])
      );
    },
    getCoreRowModel: getCoreRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    manualPagination: !!pagination?.totalRows,
    rowCount: pagination?.totalRows,
  });

  return (
    <div className={cn('space-y-4', className)}>
      {/* Toolbar */}
      <div className="flex items-center justify-between">
        {filtering && (
          <Input
            placeholder="Search..."
            value={globalFilter}
            onChange={(e) => table.setGlobalFilter(e.target.value)}
            className="max-w-sm"
            leftAddon={<Search className="h-4 w-4" />}
          />
        )}
        {actions && <div className="flex gap-2">{actions}</div>}
      </div>

      {/* Table */}
      <div className="border border-gray-800 rounded-lg overflow-hidden">
        <div className="overflow-auto max-h-[calc(100vh-300px)]">
          <Table>
            <TableHeader>
              {table.getHeaderGroups().map((headerGroup) => (
                <TableRow key={headerGroup.id}>
                  {headerGroup.headers.map((header) => (
                    <TableHead
                      key={header.id}
                      className={cn(
                        header.column.getCanSort() && 'cursor-pointer select-none',
                      )}
                      onClick={header.column.getToggleSortingHandler()}
                    >
                      <div className="flex items-center gap-2">
                        {flexRender(
                          header.column.columnDef.header,
                          header.getContext()
                        )}
                        {header.column.getCanSort() && (
                          <SortIcon
                            direction={header.column.getIsSorted()}
                          />
                        )}
                      </div>
                    </TableHead>
                  ))}
                </TableRow>
              ))}
            </TableHeader>
            <TableBody>
              {table.getRowModel().rows.length ? (
                table.getRowModel().rows.map((row) => (
                  <TableRow
                    key={row.id}
                    data-state={row.getIsSelected() && 'selected'}
                    onClick={() => row.toggleSelected()}
                  >
                    {row.getVisibleCells().map((cell) => (
                      <TableCell key={cell.id}>
                        {flexRender(
                          cell.column.columnDef.cell,
                          cell.getContext()
                        )}
                      </TableCell>
                    ))}
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell
                    colSpan={columns.length}
                    className="h-24 text-center text-gray-400"
                  >
                    <EmptyState
                      title="No results"
                      description="Try adjusting your search or filters"
                    />
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </div>
      </div>

      {/* Pagination */}
      {pagination && (
        <div className="flex items-center justify-between px-2">
          <div className="text-sm text-gray-400">
            Showing {paginationState.pageIndex * paginationState.pageSize + 1} to{' '}
            {Math.min(
              (paginationState.pageIndex + 1) * paginationState.pageSize,
              pagination.totalRows || data.length
            )}{' '}
            of {pagination.totalRows || data.length} entries
          </div>
          <div className="flex items-center gap-2">
            <Select
              value={paginationState.pageSize.toString()}
              onValueChange={(value) =>
                table.setPageSize(Number(value))
              }
            >
              <SelectTrigger className="w-20">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {[10, 20, 50, 100].map((size) => (
                  <SelectItem key={size} value={size.toString()}>
                    {size} / page
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>

            <div className="flex gap-1">
              <Button
                variant="outline"
                size="sm"
                onClick={() => table.previousPage()}
                disabled={!table.getCanPreviousPage()}
              >
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => table.nextPage()}
                disabled={!table.getCanNextPage()}
              >
                Next
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
```

---

## 8. STATE MANAGEMENT

### 8.1 Store Architecture (Zustand)

```typescript
// stores/market.store.ts
interface MarketState {
  // Market Data
  marketStatus: 'OPEN' | 'CLOSED' | 'PRE_OPEN' | 'POST_CLOSE';
  lastUpdateTime: Date | null;

  // Indices
  indices: Record<string, IndexData>;

  // Real-time quotes
  quotes: Record<string, QuoteData>;

  // Option Chain
  optionChain: OptionChainData | null;

  // Actions
  setMarketStatus: (status: MarketState['marketStatus']) => void;
  updateQuote: (symbol: string, quote: QuoteData) => void;
  updateIndices: (indices: Record<string, IndexData>) => void;
  setOptionChain: (chain: OptionChainData) => void;

  // WebSocket handlers
  handleMarketDataUpdate: (data: WebSocketMarketData) => void;
}

export const useMarketStore = create<MarketState>()(
  devtools(
    (set, get) => ({
      marketStatus: 'PRE_OPEN',
      lastUpdateTime: null,
      indices: {},
      quotes: {},
      optionChain: null,

      setMarketStatus: (status) => set({ marketStatus: status }),

      updateQuote: (symbol, quote) => set((state) => ({
        quotes: {
          ...state.quotes,
          [symbol]: {
            ...state.quotes[symbol],
            ...quote,
            lastUpdate: new Date()
          }
        }
      })),

      updateIndices: (indices) => set({ indices }),

      setOptionChain: (chain) => set({ optionChain: chain }),

      handleMarketDataUpdate: (data) => {
        const { type, payload } = data;

        switch (type) {
          case 'QUOTE':
            get().updateQuote(payload.symbol, payload);
            break;
          case 'INDICES':
            get().updateIndices(payload);
            break;
          case 'MARKET_STATUS':
            get().setMarketStatus(payload.status);
            break;
        }
      }
    }),
    { name: 'market-store' }
  )
);

// stores/positions.store.ts
interface Position {
  id: string;
  symbol: string;
  instrument: string;
  strategy: string;
  type: 'BUY' | 'SELL';
  quantity: number;
  avgEntryPrice: number;
  currentPrice: number;
  unrealizedPnL: number;
  realizedPnL: number;
  status: 'OPEN' | 'CLOSED';
  openedAt: Date;
  closedAt?: Date;
}

interface PositionsState {
  positions: Position[];
  totalUnrealizedPnL: number;
  totalRealizedPnL: number;

  // Computed
  openPositions: Position[];
  closedPositions: Position[];
  positionsByStrategy: Record<string, Position[]>;

  // Actions
  fetchPositions: () => Promise<void>;
  addPosition: (position: Position) => void;
  updatePosition: (id: string, updates: Partial<Position>) => void;
  closePosition: (id: string, realizedPnL: number) => void;
  squareOffAll: () => Promise<void>;

  // WebSocket handlers
  handlePositionUpdate: (data: WebSocketPositionData) => void;
}

export const usePositionsStore = create<PositionsState>()(
  devtools(
    (set, get) => ({
      positions: [],
      totalUnrealizedPnL: 0,
      totalRealizedPnL: 0,

      // Computed values
      get openPositions() {
        return get().positions.filter(p => p.status === 'OPEN');
      },

      get closedPositions() {
        return get().positions.filter(p => p.status === 'CLOSED');
      },

      get positionsByStrategy() {
        return get().positions.reduce((acc, pos) => {
          if (!acc[pos.strategy]) {
            acc[pos.strategy] = [];
          }
          acc[pos.strategy].push(pos);
          return acc;
        }, {} as Record<string, Position[]>);
      },

      fetchPositions: async () => {
        const response = await positionService.getPositions();
        const totalUnrealizedPnL = response.positions
          .filter(p => p.status === 'OPEN')
          .reduce((sum, p) => sum + p.unrealizedPnL, 0);
        const totalRealizedPnL = response.positions
          .filter(p => p.status === 'CLOSED')
          .reduce((sum, p) => sum + p.realizedPnL, 0);

        set({
          positions: response.positions,
          totalUnrealizedPnL,
          totalRealizedPnL
        });
      },

      addPosition: (position) => set((state) => ({
        positions: [...state.positions, position]
      })),

      updatePosition: (id, updates) => set((state) => ({
        positions: state.positions.map(p =>
          p.id === id ? { ...p, ...updates } : p
        )
      })),

      closePosition: (id, realizedPnL) => set((state) => ({
        positions: state.positions.map(p =>
          p.id === id
            ? { ...p, status: 'CLOSED', realizedPnL, closedAt: new Date() }
            : p
        ),
        totalRealizedPnL: state.totalRealizedPnL + realizedPnL
      })),

      squareOffAll: async () => {
        await positionService.squareOffAll();
        await get().fetchPositions();
      },

      handlePositionUpdate: (data) => {
        const { type, payload } = data;

        switch (type) {
          case 'NEW_POSITION':
            get().addPosition(payload);
            break;
          case 'UPDATE_POSITION':
            get().updatePosition(payload.id, payload);
            break;
          case 'POSITION_CLOSED':
            get().closePosition(payload.id, payload.realizedPnL);
            break;
        }
      }
    }),
    { name: 'positions-store' }
  )
);

// stores/orders.store.ts
interface Order {
  id: string;
  instrument: string;
  type: 'MARKET' | 'LIMIT' | 'SL' | 'SL-M';
  side: 'BUY' | 'SELL';
  quantity: number;
  price?: number;
  triggerPrice?: number;
  status: 'PENDING' | 'OPEN' | 'FILLED' | 'CANCELLED' | 'REJECTED';
  strategy?: string;
  createdAt: Date;
  filledAt?: Date;
  filledPrice?: number;
  filledQuantity: number;
}

interface OrdersState {
  orders: Order[];
  filters: {
    status: string[];
    dateRange: { from: Date; to: Date };
    strategy?: string;
  };

  // Actions
  fetchOrders: (filters?: OrdersState['filters']) => Promise<void>;
  placeOrder: (order: Partial<Order>) => Promise<void>;
  cancelOrder: (orderId: string) => Promise<void>;
  modifyOrder: (orderId: string, updates: Partial<Order>) => Promise<void>;
  setFilters: (filters: Partial<OrdersState['filters']>) => void;

  // WebSocket handlers
  handleOrderUpdate: (data: WebSocketOrderData) => void;
}

export const useOrdersStore = create<OrdersState>()(
  devtools(
    (set, get) => ({
      orders: [],
      filters: {
        status: [],
        dateRange: {
          from: startOfDay(new Date()),
          to: endOfDay(new Date())
        }
      },

      fetchOrders: async (filters) => {
        const queryFilters = filters || get().filters;
        const response = await orderService.getOrders(queryFilters);
        set({ orders: response.orders });
      },

      placeOrder: async (orderData) => {
        const newOrder = await orderService.placeOrder(orderData);
        set((state) => ({
          orders: [newOrder, ...state.orders]
        }));
      },

      cancelOrder: async (orderId) => {
        await orderService.cancelOrder(orderId);
        set((state) => ({
          orders: state.orders.map(o =>
            o.id === orderId ? { ...o, status: 'CANCELLED' } : o
          )
        }));
      },

      modifyOrder: async (orderId, updates) => {
        await orderService.modifyOrder(orderId, updates);
        set((state) => ({
          orders: state.orders.map(o =>
            o.id === orderId ? { ...o, ...updates } : o
          )
        }));
      },

      setFilters: (filters) => set((state) => ({
        filters: { ...state.filters, ...filters }
      })),

      handleOrderUpdate: (data) => {
        const { type, payload } = data;

        switch (type) {
          case 'ORDER_CREATED':
            set((state) => ({
              orders: [payload, ...state.orders]
            }));
            break;
          case 'ORDER_UPDATED':
            set((state) => ({
              orders: state.orders.map(o =>
                o.id === payload.id ? { ...o, ...payload } : o
              )
            }));
            break;
          case 'ORDER_FILLED':
            set((state) => ({
              orders: state.orders.map(o =>
                o.id === payload.id
                  ? { ...o, status: 'FILLED', filledAt: payload.filledAt, filledPrice: payload.filledPrice }
                  : o
              )
            }));
            break;
        }
      }
    }),
    { name: 'orders-store' }
  )
);

// stores/ui.store.ts
interface UIState {
  sidebarCollapsed: boolean;
  theme: 'dark' | 'light';
  activeModal: string | null;
  toasts: Toast[];

  // Actions
  toggleSidebar: () => void;
  setSidebarCollapsed: (collapsed: boolean) => void;
  setTheme: (theme: UIState['theme']) => void;
  openModal: (modalId: string) => void;
  closeModal: (modalId: string) => void;
  addToast: (toast: Omit<Toast, 'id'>) => string;
  removeToast: (id: string) => void;
}

export const useUIStore = create<UIState>()(
  devtools(
    (set) => ({
      sidebarCollapsed: false,
      theme: 'dark',
      activeModal: null,
      toasts: [],

      toggleSidebar: () => set((state) => ({
        sidebarCollapsed: !state.sidebarCollapsed
      })),

      setSidebarCollapsed: (collapsed) => set({ sidebarCollapsed: collapsed }),

      setTheme: (theme) => set({ theme }),

      openModal: (modalId) => set({ activeModal: modalId }),

      closeModal: () => set({ activeModal: null }),

      addToast: (toast) => {
        const id = Math.random().toString(36).substr(2, 9);
        set((state) => ({
          toasts: [...state.toasts, { ...toast, id }]
        }));
        return id;
      },

      removeToast: (id) => set((state) => ({
        toasts: state.toasts.filter(t => t.id !== id)
      }))
    }),
    { name: 'ui-store' }
  )
);
```

### 8.2 React Query Setup

```typescript
// lib/react-query.ts
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      gcTime: 1000 * 60 * 30, // 30 minutes
      retry: 1,
      refetchOnWindowFocus: false,
      refetchOnReconnect: true,
    },
    mutations: {
      retry: 0,
    },
  },
});

export { queryClient, QueryClientProvider, ReactQueryDevtools };

// hooks/useQuery.ts - Custom hooks for common queries
export const useMarketData = (symbol: string, timeframe: string) => {
  return useQuery({
    queryKey: ['market-data', symbol, timeframe],
    queryFn: () => marketService.getOHLCData(symbol, timeframe),
    refetchInterval: timeframe === '1m' ? 1000 * 60 : false,
  });
};

export const usePositions = () => {
  return useQuery({
    queryKey: ['positions'],
    queryFn: () => positionService.getPositions(),
    refetchInterval: 5000, // Refresh every 5 seconds
  });
};

export const useOrders = (filters?: OrderFilters) => {
  return useQuery({
    queryKey: ['orders', filters],
    queryFn: () => orderService.getOrders(filters),
  });
};

export const useOptionChain = (symbol: string, expiry: string) => {
  return useQuery({
    queryKey: ['option-chain', symbol, expiry],
    queryFn: () => marketService.getOptionChain(symbol, expiry),
    refetchInterval: 3000, // Refresh every 3 seconds
  });
};
```

---

## 9. ROUTING & NAVIGATION

### 9.1 Route Configuration

```typescript
// constants/routes.ts
export const ROUTES = {
  // Auth
  LOGIN: '/login',
  REGISTER: '/register',

  // Main
  DASHBOARD: '/dashboard',

  // Market
  MARKET_WATCH: '/market-watch',
  OPTION_CHAIN: '/option-chain',
  MARKET_DATA: '/market-data/:symbol',

  // Portfolio
  POSITIONS: '/positions',
  ORDERS: '/orders',
  HOLDINGS: '/holdings',
  FUNDS: '/funds',

  // Analytics
  REPORTS: '/reports',
  PERFORMANCE: '/performance',
  TRADE_LOG: '/trade-log',

  // Strategies
  STRATEGIES: '/strategies',
  STRATEGY_CREATOR: '/strategies/creator',
  STRATEGY_DETAIL: '/strategies/:id',
  BACKTESTER: '/backtester',
  REPLAY: '/replay',

  // System
  LOGS: '/logs',
  ALERTS: '/alerts',
  SCHEDULER: '/scheduler',
  SETTINGS: '/settings',

  // News
  NEWS_EVENTS: '/news-events',
} as const;

// lib/config/routes.ts
export const navigationConfig = {
  main: [
    {
      id: 'dashboard',
      label: 'Dashboard',
      href: ROUTES.DASHBOARD,
      icon: LayoutDashboard,
    },
    {
      id: 'strategies',
      label: 'Strategies',
      href: ROUTES.STRATEGIES,
      icon: Workflow,
    },
    {
      id: 'backtester',
      label: 'Backtester',
      href: ROUTES.BACKTESTER,
      icon: BarChart3,
    },
    {
      id: 'replay',
      label: 'Replay',
      href: ROUTES.REPLAY,
      icon: Rewind,
    },
  ],
  market: [
    {
      id: 'market-watch',
      label: 'Market Watch',
      href: ROUTES.MARKET_WATCH,
      icon: Eye,
    },
    {
      id: 'option-chain',
      label: 'Option Chain',
      href: ROUTES.OPTION_CHAIN,
      icon: Link2,
    },
    {
      id: 'market-data',
      label: 'Market Data',
      href: ROUTES.MARKET_DATA.replace(':symbol', 'NIFTY'),
      icon: TrendingUp,
    },
    {
      id: 'news-events',
      label: 'News & Events',
      href: ROUTES.NEWS_EVENTS,
      icon: Newspaper,
    },
  ],
  portfolio: [
    {
      id: 'positions',
      label: 'Positions',
      href: ROUTES.POSITIONS,
      icon: Briefcase,
      badge: 'live',
    },
    {
      id: 'orders',
      label: 'Orders',
      href: ROUTES.ORDERS,
      icon: ClipboardList,
    },
    {
      id: 'holdings',
      label: 'Holdings',
      href: ROUTES.HOLDINGS,
      icon: PieChart,
    },
    {
      id: 'funds',
      label: 'Funds',
      href: ROUTES.FUNDS,
      icon: Wallet,
    },
  ],
  analytics: [
    {
      id: 'reports',
      label: 'Reports',
      href: ROUTES.REPORTS,
      icon: FileText,
    },
    {
      id: 'performance',
      label: 'Performance',
      href: ROUTES.PERFORMANCE,
      icon: TrendingUp,
    },
    {
      id: 'trade-log',
      label: 'Trade Log',
      href: ROUTES.TRADE_LOG,
      icon: ScrollText,
    },
  ],
  system: [
    {
      id: 'logs',
      label: 'Logs',
      href: ROUTES.LOGS,
      icon: FileCode,
    },
    {
      id: 'alerts',
      label: 'Alerts',
      href: ROUTES.ALERTS,
      icon: Bell,
      badge: 5,
    },
    {
      id: 'scheduler',
      label: 'Scheduler',
      href: ROUTES.SCHEDULER,
      icon: CalendarClock,
    },
    {
      id: 'settings',
      label: 'Settings',
      href: ROUTES.SETTINGS,
      icon: Settings,
    },
  ],
};
```

### 9.2 Route Guards

```typescript
// components/auth/AuthGuard.tsx
interface AuthGuardProps {
  children: React.ReactNode;
  requireAuth?: boolean;
  allowedRoles?: string[];
}

export const AuthGuard: React.FC<AuthGuardProps> = ({
  children,
  requireAuth = true,
  allowedRoles
}) => {
  const { user, isAuthenticated, isLoading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!isLoading) {
      if (requireAuth && !isAuthenticated) {
        router.push(ROUTES.LOGIN);
      } else if (isAuthenticated && allowedRoles && !allowedRoles.includes(user?.role || '')) {
        router.push(ROUTES.DASHBOARD);
      }
    }
  }, [isAuthenticated, isLoading, user, requireAuth, allowedRoles, router]);

  if (isLoading) {
    return <LoadingScreen />;
  }

  if (requireAuth && !isAuthenticated) {
    return null;
  }

  return <>{children}</>;
};

// middleware.ts (Next.js Middleware)
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const token = request.cookies.get('auth_token');
  const { pathname } = request.nextUrl;

  // Protected routes
  const protectedRoutes = ['/dashboard', '/positions', '/orders', '/strategies'];

  if (protectedRoutes.some(route => pathname.startsWith(route))) {
    if (!token) {
      const loginUrl = new URL('/login', request.url);
      loginUrl.searchParams.set('redirect', pathname);
      return NextResponse.redirect(loginUrl);
    }
  }

  // Auth routes redirect if already logged in
  if (pathname === '/login' || pathname === '/register') {
    if (token) {
      return NextResponse.redirect(new URL('/dashboard', request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
};
```

---

## 10. API INTEGRATION LAYER

### 10.1 API Client Setup

```typescript
// lib/api/client.ts
import axios, { AxiosInstance, AxiosError, InternalAxiosRequestConfig } from 'axios';
import { ROUTES } from '@/constants/routes';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'https://api.dhan.co/v2';

class ApiClient {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config: InternalAxiosRequestConfig) => {
        // Add auth token
        const token = this.getAuthToken();
        if (token && config.headers) {
          config.headers.Authorization = `Bearer ${token}`;
        }

        // Add client ID for Dhan API
        const clientId = process.env.NEXT_PUBLIC_DHAN_CLIENT_ID;
        if (clientId && config.headers) {
          config.headers['client-id'] = clientId;
        }

        return config;
      },
      (error: AxiosError) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError) => {
        const originalRequest = error.config as InternalAxiosRequestConfig & {
          _retry?: boolean;
        };

        // Handle 401 - Token expired
        if (error.response?.status === 401 && !originalRequest._retry) {
          originalRequest._retry = true;

          try {
            const newToken = await this.refreshToken();
            if (originalRequest.headers) {
              originalRequest.headers.Authorization = `Bearer ${newToken}`;
            }
            return this.client(originalRequest);
          } catch (refreshError) {
            // Clear auth and redirect to login
            this.clearAuth();
            window.location.href = ROUTES.LOGIN;
            return Promise.reject(refreshError);
          }
        }

        // Handle other errors
        return Promise.reject(this.handleError(error));
      }
    );
  }

  private getAuthToken(): string | null {
    if (typeof window === 'undefined') return null;
    return localStorage.getItem('auth_token');
  }

  private async refreshToken(): Promise<string> {
    const refreshToken = localStorage.getItem('refresh_token');
    if (!refreshToken) throw new Error('No refresh token');

    const response = await axios.post(`${API_BASE_URL}/auth/refresh`, {
      refresh_token: refreshToken,
    });

    const { access_token, refresh_token: newRefreshToken } = response.data;
    localStorage.setItem('auth_token', access_token);
    localStorage.setItem('refresh_token', newRefreshToken);

    return access_token;
  }

  private clearAuth() {
    localStorage.removeItem('auth_token');
    localStorage.removeItem('refresh_token');
  }

  private handleError(error: AxiosError) {
    const message = (error.response?.data as any)?.message || error.message;
    const code = error.response?.status || 500;

    return {
      code,
      message,
      originalError: error,
    };
  }

  // HTTP methods
  async get<T>(url: string, config?: any): Promise<T> {
    const response = await this.client.get<T>(url, config);
    return response.data;
  }

  async post<T>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.post<T>(url, data, config);
    return response.data;
  }

  async put<T>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.put<T>(url, data, config);
    return response.data;
  }

  async patch<T>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.patch<T>(url, data, config);
    return response.data;
  }

  async delete<T>(url: string, config?: any): Promise<T> {
    const response = await this.client.delete<T>(url, config);
    return response.data;
  }
}

export const apiClient = new ApiClient();
```

### 10.2 API Endpoints

```typescript
// lib/api/endpoints.ts
export const endpoints = {
  // Auth
  auth: {
    login: '/auth/login',
    register: '/auth/register',
    logout: '/auth/logout',
    refreshToken: '/auth/refresh',
    me: '/auth/me',
  },

  // Market Data
  market: {
    quote: '/market/quote',
    ohlc: '/market/ohlc',
    depth: '/market/depth',
    indices: '/market/indices',
    optionChain: '/market/option-chain',
    historical: '/market/historical',
  },

  // Orders
  orders: {
    list: '/orders',
    place: '/orders/place',
    modify: '/orders/modify',
    cancel: '/orders/cancel',
    details: (id: string) => `/orders/${id}`,
  },

  // Positions
  positions: {
    list: '/positions',
    squareOff: '/positions/square-off',
    squareOffAll: '/positions/square-off-all',
  },

  // Holdings
  holdings: {
    list: '/holdings',
  },

  // Funds
  funds: {
    balance: '/funds/balance',
    ledger: '/funds/ledger',
    addFunds: '/funds/add',
    withdraw: '/funds/withdraw',
  },

  // Strategies
  strategies: {
    list: '/strategies',
    create: '/strategies',
    update: (id: string) => `/strategies/${id}`,
    delete: (id: string) => `/strategies/${id}`,
    backtest: (id: string) => `/strategies/${id}/backtest`,
    deploy: (id: string) => `/strategies/${id}/deploy`,
  },

  // Reports
  reports: {
    pnl: '/reports/pnl',
    trades: '/reports/trades',
    performance: '/reports/performance',
    export: '/reports/export',
  },

  // Alerts
  alerts: {
    list: '/alerts',
    create: '/alerts',
    update: (id: string) => `/alerts/${id}`,
    delete: (id: string) => `/alerts/${id}`,
  },

  // Scheduler
  scheduler: {
    tasks: '/scheduler/tasks',
    create: '/scheduler/tasks',
    execute: (id: string) => `/scheduler/tasks/${id}/execute`,
  },

  // Logs
  logs: {
    list: '/logs',
    export: '/logs/export',
  },
};
```

### 10.3 Service Layer

```typescript
// services/trading.service.ts
export const tradingService = {
  // Market Data
  getQuote: async (symbol: string) => {
    return apiClient.get<QuoteData>(endpoints.market.quote, {
      params: { symbol },
    });
  },

  getOHLCData: async (symbol: string, timeframe: string, from: Date, to: Date) => {
    return apiClient.get<OHLCData[]>(endpoints.market.ohlc, {
      params: { symbol, timeframe, from: from.toISOString(), to: to.toISOString() },
    });
  },

  getMarketDepth: async (symbol: string) => {
    return apiClient.get<MarketDepthData>(endpoints.market.depth, {
      params: { symbol },
    });
  },

  getOptionChain: async (symbol: string, expiry: string) => {
    return apiClient.get<OptionChainData>(endpoints.market.optionChain, {
      params: { symbol, expiry },
    });
  },

  // Orders
  placeOrder: async (orderData: OrderPayload) => {
    return apiClient.post<Order>(endpoints.orders.place, orderData);
  },

  modifyOrder: async (orderId: string, updates: Partial<OrderPayload>) => {
    return apiClient.put<Order>(endpoints.orders.modify, { order_id: orderId, ...updates });
  },

  cancelOrder: async (orderId: string) => {
    return apiClient.delete<Order>(`${endpoints.orders.cancel}?order_id=${orderId}`);
  },

  getOrders: async (filters?: OrderFilters) => {
    return apiClient.get<Order[]>(endpoints.orders.list, { params: filters });
  },

  // Positions
  getPositions: async () => {
    return apiClient.get<Position[]>(endpoints.positions.list);
  },

  squareOffPosition: async (positionId: string) => {
    return apiClient.post(endpoints.positions.squareOff, { position_id: positionId });
  },

  squareOffAll: async () => {
    return apiClient.post(endpoints.positions.squareOffAll);
  },

  // Holdings
  getHoldings: async () => {
    return apiClient.get<Holding[]>(endpoints.holdings.list);
  },

  // Funds
  getFunds: async () => {
    return apiClient.get<FundsData>(endpoints.funds.balance);
  },

  addFunds: async (amount: number, mode: 'UPI' | 'NET_BANKING') => {
    return apiClient.post(endpoints.funds.addFunds, { amount, mode });
  },

  withdrawFunds: async (amount: number) => {
    return apiClient.post(endpoints.funds.withdraw, { amount });
  },

  // Strategies
  getStrategies: async () => {
    return apiClient.get<Strategy[]>(endpoints.strategies.list);
  },

  createStrategy: async (strategyData: StrategyPayload) => {
    return apiClient.post<Strategy>(endpoints.strategies.create, strategyData);
  },

  backtestStrategy: async (strategyId: string, params: BacktestParams) => {
    return apiClient.post<BacktestResult>(
      endpoints.strategies.backtest(strategyId),
      params
    );
  },

  deployStrategy: async (strategyId: string, config: DeployConfig) => {
    return apiClient.post(endpoints.strategies.deploy(strategyId), config);
  },
};
```

---

## 11. WEBSOCKET INTEGRATION

### 11.1 WebSocket Client

```typescript
// lib/websocket/client.ts
type WebSocketMessage = {
  type: string;
  payload: any;
  timestamp: number;
};

type WebSocketEventHandler = (data: any) => void;

class WebSocketClient {
  private ws: WebSocket | null = null;
  private url: string;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;
  private eventHandlers: Map<string, Set<WebSocketEventHandler>> = new Map();
  private messageQueue: WebSocketMessage[] = [];
  private heartbeatInterval: NodeJS.Timeout | null = null;

  constructor(url: string) {
    this.url = url;
  }

  connect() {
    try {
      const token = localStorage.getItem('auth_token');
      const wsUrl = `${this.url}?token=${token}`;

      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        console.log('WebSocket connected');
        this.reconnectAttempts = 0;
        this.startHeartbeat();
        this.flushMessageQueue();
      };

      this.ws.onmessage = (event) => {
        try {
          const data: WebSocketMessage = JSON.parse(event.data);
          this.handleMessage(data);
        } catch (error) {
          console.error('WebSocket message parse error:', error);
        }
      };

      this.ws.onclose = () => {
        console.log('WebSocket disconnected');
        this.stopHeartbeat();
        this.attemptReconnect();
      };

      this.ws.onerror = (error) => {
        console.error('WebSocket error:', error);
      };
    } catch (error) {
      console.error('Failed to create WebSocket connection:', error);
      this.attemptReconnect();
    }
  }

  private attemptReconnect() {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);

      console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);

      setTimeout(() => {
        this.connect();
      }, delay);
    } else {
      console.error('Max reconnection attempts reached');
      this.emit('connection_failed', { attempts: this.maxReconnectAttempts });
    }
  }

  private startHeartbeat() {
    this.heartbeatInterval = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ type: 'ping' }));
      }
    }, 30000); // Send ping every 30 seconds
  }

  private stopHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  private handleMessage(message: WebSocketMessage) {
    if (message.type === 'pong') {
      return; // Heartbeat response
    }

    this.emit(message.type, message.payload);
  }

  private flushMessageQueue() {
    while (this.messageQueue.length > 0 && this.ws?.readyState === WebSocket.OPEN) {
      const message = this.messageQueue.shift();
      if (message && this.ws) {
        this.ws.send(JSON.stringify(message));
      }
    }
  }

  send(type: string, payload: any) {
    const message: WebSocketMessage = {
      type,
      payload,
      timestamp: Date.now(),
    };

    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    } else {
      this.messageQueue.push(message);
    }
  }

  on(event: string, handler: WebSocketEventHandler) {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event)!.add(handler);
  }

  off(event: string, handler: WebSocketEventHandler) {
    this.eventHandlers.get(event)?.delete(handler);
  }

  private emit(event: string, data: any) {
    this.eventHandlers.get(event)?.forEach(handler => handler(data));
  }

  disconnect() {
    this.stopHeartbeat();
    this.ws?.close();
    this.ws = null;
  }
}

export const wsClient = new WebSocketClient(
  process.env.NEXT_PUBLIC_WS_URL || 'wss://api.dhan.co/v2/ws'
);
```

### 11.2 WebSocket Event Handlers

```typescript
// lib/websocket/handlers.ts
export const setupWebSocketHandlers = () => {
  // Market data updates
  wsClient.on('quote', (data: QuoteData) => {
    useMarketStore.getState().updateQuote(data.symbol, data);
  });

  wsClient.on('indices', (data: Record<string, IndexData>) => {
    useMarketStore.getState().updateIndices(data);
  });

  // Order updates
  wsClient.on('order_created', (data: Order) => {
    useOrdersStore.getState().handleOrderUpdate({ type: 'ORDER_CREATED', payload: data });
  });

  wsClient.on('order_updated', (data: Partial<Order> & { id: string }) => {
    useOrdersStore.getState().handleOrderUpdate({ type: 'ORDER_UPDATED', payload: data });
  });

  wsClient.on('order_filled', (data: Order) => {
    useOrdersStore.getState().handleOrderUpdate({ type: 'ORDER_FILLED', payload: data });
  });

  // Position updates
  wsClient.on('position_opened', (data: Position) => {
    usePositionsStore.getState().handlePositionUpdate({ type: 'NEW_POSITION', payload: data });
  });

  wsClient.on('position_updated', (data: Position) => {
    usePositionsStore.getState().handlePositionUpdate({ type: 'UPDATE_POSITION', payload: data });
  });

  wsClient.on('position_closed', (data: Position) => {
    usePositionsStore.getState().handlePositionUpdate({ type: 'POSITION_CLOSED', payload: data });
  });

  // System events
  wsClient.on('market_status', (data: { status: MarketStatus }) => {
    useMarketStore.getState().setMarketStatus(data.status);
  });

  wsClient.on('alert_triggered', (data: Alert) => {
    // Show toast notification
    const { toast } = useToast();
    toast({
      title: 'Alert Triggered',
      description: data.message,
      variant: 'info',
    });
  });

  // Connection status
  wsClient.on('connection_failed', () => {
    const { toast } = useToast();
    toast({
      title: 'Connection Lost',
      description: 'Real-time updates are temporarily unavailable',
      variant: 'warning',
    });
  });
};

// components/WebSocketProvider.tsx
export const WebSocketProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  useEffect(() => {
    setupWebSocketHandlers();
    wsClient.connect();

    return () => {
      wsClient.disconnect();
    };
  }, []);

  return <>{children}</>;
};
```

---

## 12. TYPESCRIPT INTERFACES

```typescript
// types/trading.types.ts
export type MarketStatus = 'OPEN' | 'CLOSED' | 'PRE_OPEN' | 'POST_CLOSE';

export type OrderType = 'MARKET' | 'LIMIT' | 'SL' | 'SL-M';

export type OrderSide = 'BUY' | 'SELL';

export type OrderStatus =
  | 'PENDING'
  | 'OPEN'
  | 'FILLED'
  | 'PARTIALLY_FILLED'
  | 'CANCELLED'
  | 'REJECTED';

export type ProductType = 'INTRADAY' | 'CNC' | 'MARGIN';

export type Segment = 'NFO' | 'BFO' | 'CDS' | 'MCX';

export interface QuoteData {
  symbol: string;
  ltp: number;
  open: number;
  high: number;
  low: number;
  close: number;
  change: number;
  changePercent: number;
  volume: number;
  value: number;
  lastTradeTime: Date;
  bidPrice: number;
  bidQty: number;
  askPrice: number;
  askQty: number;
}

export interface OHLCData {
  timestamp: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface MarketDepthLevel {
  price: number;
  qty: number;
  orders: number;
}

export interface MarketDepthData {
  symbol: string;
  bid: MarketDepthLevel[];
  ask: MarketDepthLevel[];
  totalBidQty: number;
  totalAskQty: number;
}

export interface OptionData {
  symbol: string;
  strike: number;
  expiry: string;
  type: 'CE' | 'PE';
  ltp: number;
  oi: number;
  changeInOI: number;
  volume: number;
  iv: number;
  delta: number;
  gamma: number;
  theta: number;
  vega: number;
  underlying: string;
}

export interface OptionChainData {
  underlying: string;
  spotPrice: number;
  expiry: string;
  strikes: OptionData[];
  pcr: number;
  maxPain: number;
  totalCallOI: number;
  totalPutOI: number;
}

export interface Order {
  id: string;
  instrument: string;
  symbol: string;
  type: OrderType;
  side: OrderSide;
  quantity: number;
  price?: number;
  triggerPrice?: number;
  status: OrderStatus;
  product: ProductType;
  strategy?: string;
  createdAt: Date;
  updatedAt: Date;
  filledAt?: Date;
  filledPrice?: number;
  filledQuantity: number;
  pendingQuantity: number;
  exchangeOrderId?: string;
  rejectionReason?: string;
}

export interface OrderPayload {
  instrument: string;
  type: OrderType;
  side: OrderSide;
  quantity: number;
  price?: number;
  triggerPrice?: number;
  product: ProductType;
  strategy?: string;
}

export interface Position {
  id: string;
  symbol: string;
  instrument: string;
  strategy: string;
  type: OrderSide;
  quantity: number;
  avgEntryPrice: number;
  currentPrice: number;
  unrealizedPnL: number;
  realizedPnL: number;
  status: 'OPEN' | 'CLOSED';
  openedAt: Date;
  closedAt?: Date;
}

export interface Holding {
  symbol: string;
  company: string;
  assetType: 'STOCK' | 'ETF' | 'OTHER';
  exchange: string;
  quantity: number;
  avgPrice: number;
  currentPrice: number;
  investment: number;
  currentValue: number;
  pnl: number;
  pnlPercent: number;
  dayChange: number;
  dayChangePercent: number;
}

export interface FundsData {
  availableFunds: number;
  utilizedMargin: number;
  totalFunds: number;
  unrealizedPnL: number;
  dayPnL: number;
  cashBalance: number;
  buyingPower: number;
  marginUtilization: number;
}

export interface Strategy {
  id: string;
  name: string;
  description: string;
  type: 'VISUAL' | 'CODE';
  code?: string;
  language?: 'RUBY' | 'PYTHON' | 'JAVASCRIPT';
  parameters: Record<string, any>;
  instruments: string[];
  timeframe: string;
  status: 'DRAFT' | 'ACTIVE' | 'PAUSED' | 'STOPPED';
  createdAt: Date;
  updatedAt: Date;
  backtestResult?: BacktestResult;
}

export interface BacktestResult {
  netProfit: number;
  totalReturn: number;
  totalTrades: number;
  winRate: number;
  profitFactor: number;
  maxDrawdown: number;
  sharpeRatio: number;
  sortinoRatio: number;
  expectancy: number;
  trades: Trade[];
  equityCurve: EquityPoint[];
}

export interface Trade {
  id: string;
  entryTime: Date;
  exitTime?: Date;
  instrument: string;
  side: OrderSide;
  quantity: number;
  entryPrice: number;
  exitPrice?: number;
  pnl: number;
  pnlPercent: number;
  status: 'OPEN' | 'CLOSED';
  strategy: string;
}

export interface EquityPoint {
  timestamp: Date;
  equity: number;
  drawdown: number;
}

export interface Alert {
  id: string;
  name: string;
  type: 'PRICE' | 'INDICATOR' | 'STRATEGY' | 'SYSTEM';
  condition: string;
  symbol?: string;
  strategy?: string;
  status: 'ACTIVE' | 'PAUSED' | 'TRIGGERED' | 'DISABLED';
  channels: ('WEB_PUSH' | 'EMAIL' | 'TELEGRAM' | 'SMS')[];
  lastTriggered?: Date;
  createdAt: Date;
}

export interface ScheduledTask {
  id: string;
  name: string;
  type: 'STRATEGY' | 'DATA_JOB' | 'SYSTEM' | 'NOTIFICATION';
  module: string;
  schedule: string; // Cron expression
  nextRun: Date;
  lastRun?: Date;
  lastRunStatus?: 'SUCCESS' | 'FAILED';
  status: 'ACTIVE' | 'PAUSED' | 'DISABLED';
  createdAt: Date;
}

// types/user.types.ts
export interface User {
  id: string;
  name: string;
  email: string;
  phone?: string;
  role: 'USER' | 'ADMIN';
  plan: 'FREE' | 'PRO' | 'PREMIUM';
  clientId: string;
  createdAt: Date;
}

export interface UserProfile {
  tradingPreferences: {
    defaultMarket: string;
    defaultSegment: Segment;
    defaultOrderType: OrderType;
    defaultProduct: ProductType;
    defaultTimeframe: string;
    riskPerTrade: number;
    maxDailyLoss: number;
    maxOpenPositions: number;
  };
  notifications: {
    orderExecuted: boolean;
    orderUpdate: boolean;
    positionUpdate: boolean;
    alertTriggered: boolean;
    dailyPnL: boolean;
  };
  appearance: {
    theme: 'DARK' | 'LIGHT';
    colorScheme: string;
    compactMode: boolean;
  };
}

// types/common.types.ts
export type PaginationParams = {
  page: number;
  limit: number;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
};

export type ApiResponse<T> = {
  data: T;
  meta?: {
    total: number;
    page: number;
    limit: number;
    totalPages: number;
  };
  success: boolean;
  message?: string;
};

export type ErrorResponse = {
  code: number;
  message: string;
  errors?: Record<string, string[]>;
};

export type WebSocketMarketData =
  | { type: 'QUOTE'; payload: QuoteData }
  | { type: 'INDICES'; payload: Record<string, IndexData> }
  | { type: 'MARKET_STATUS'; payload: { status: MarketStatus } };

export type WebSocketOrderData =
  | { type: 'ORDER_CREATED'; payload: Order }
  | { type: 'ORDER_UPDATED'; payload: Partial<Order> & { id: string } }
  | { type: 'ORDER_FILLED'; payload: Order };

export type WebSocketPositionData =
  | { type: 'NEW_POSITION'; payload: Position }
  | { type: 'UPDATE_POSITION'; payload: Position }
  | { type: 'POSITION_CLOSED'; payload: Position };
```

---

## 13. STYLING SYSTEM

### 13.1 Tailwind Configuration

```javascript
// tailwind.config.js
/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: ['class'],
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './features/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
        // Trading-specific colors
        profit: {
          DEFAULT: '#22C55E',
          light: '#4ADE80',
          dark: '#16A34A',
        },
        loss: {
          DEFAULT: '#EF4444',
          light: '#F87171',
          dark: '#DC2626',
        },
        neutral: {
          DEFAULT: '#6B7280',
          light: '#9CA3AF',
          dark: '#4B5563',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['Fira Code', 'monospace'],
      },
      keyframes: {
        'accordion-down': {
          from: { height: 0 },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: 0 },
        },
        'pulse-slow': {
          '0%, 100%': { opacity: 1 },
          '50%': { opacity: 0.5 },
        },
      },
      animation: {
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
        'pulse-slow': 'pulse-slow 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
};
```

### 13.2 CSS Variables

```css
/* styles/variables.css */
:root {
  /* Dark Theme (Default) */
  --background: 222.2 84% 4.9%;
  --foreground: 210 40% 98%;
  --card: 222.2 84% 4.9%;
  --card-foreground: 210 40% 98%;
  --popover: 222.2 84% 4.9%;
  --popover-foreground: 210 40% 98%;
  --primary: 142 76% 36%;
  --primary-foreground: 355.7 100% 97.3%;
  --secondary: 217.2 32.6% 17.5%;
  --secondary-foreground: 210 40% 98%;
  --muted: 217.2 32.6% 17.5%;
  --muted-foreground: 215 20.2% 65.1%;
  --accent: 217.2 32.6% 17.5%;
  --accent-foreground: 210 40% 98%;
  --destructive: 0 62.8% 30.6%;
  --destructive-foreground: 210 40% 98%;
  --border: 217.2 32.6% 17.5%;
  --input: 217.2 32.6% 17.5%;
  --ring: 142 76% 36%;
  --radius: 0.5rem;
}

.light {
  --background: 0 0% 100%;
  --foreground: 222.2 84% 4.9%;
  --card: 0 0% 100%;
  --card-foreground: 222.2 84% 4.9%;
  --popover: 0 0% 100%;
  --popover-foreground: 222.2 84% 4.9%;
  --primary: 142 76% 36%;
  --primary-foreground: 355.7 100% 97.3%;
  --secondary: 210 40% 96.1%;
  --secondary-foreground: 222.2 47.4% 11.2%;
  --muted: 210 40% 96.1%;
  --muted-foreground: 215.4 16.3% 46.9%;
  --accent: 210 40% 96.1%;
  --accent-foreground: 222.2 47.4% 11.2%;
  --destructive: 0 84.2% 60.2%;
  --destructive-foreground: 210 40% 98%;
  --border: 214.3 31.8% 91.4%;
  --input: 214.3 31.8% 91.4%;
  --ring: 142 76% 36%;
}

/* Spacing */
:root {
  --sidebar-width: 16rem;
  --sidebar-width-collapsed: 4rem;
  --header-height: 3.5rem;
}

/* Typography */
:root {
  --font-sans: 'Inter', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  --font-mono: 'Fira Code', 'Courier New', monospace;
}
```

### 13.3 Utility Classes

```css
/* styles/utilities.css */
@layer utilities {
  /* Scrollbar styling */
  .scrollbar-thin {
    scrollbar-width: thin;
    scrollbar-color: hsl(var(--muted)) transparent;
  }

  .scrollbar-thin::-webkit-scrollbar {
    width: 6px;
    height: 6px;
  }

  .scrollbar-thin::-webkit-scrollbar-track {
    background: transparent;
  }

  .scrollbar-thin::-webkit-scrollbar-thumb {
    background-color: hsl(var(--muted));
    border-radius: 20px;
  }

  /* Text truncation */
  .line-clamp-2 {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  /* Glass effect */
  .glass {
    background: rgba(255, 255, 255, 0.05);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255, 255, 255, 0.1);
  }

  /* Trading-specific utilities */
  .text-profit {
    color: #22C55E;
  }

  .text-loss {
    color: #EF4444;
  }

  .bg-profit {
    background-color: #22C55E;
  }

  .bg-loss {
    background-color: #EF4444;
  }

  /* Animation utilities */
  .animate-fade-in {
    animation: fadeIn 0.3s ease-in-out;
  }

  .animate-slide-up {
    animation: slideUp 0.3s ease-out;
  }

  @keyframes fadeIn {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  @keyframes slideUp {
    from {
      transform: translateY(10px);
      opacity: 0;
    }
    to {
      transform: translateY(0);
      opacity: 1;
    }
  }
}
```

---

## 14. UTILITIES & HELPERS

### 14.1 Formatters

```typescript
// utils/formatters/currency.ts
export const formatCurrency = (
  value: number,
  currency: string = 'INR',
  options?: Intl.NumberFormatOptions
): string => {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    ...options,
  }).format(value);
};

export const formatPrice = (price: number): string => {
  return price.toFixed(2);
};

export const formatLakhsCrores = (value: number): string => {
  if (value >= 10000000) {
    return `₹${(value / 10000000).toFixed(2)} Cr`;
  } else if (value >= 100000) {
    return `₹${(value / 100000).toFixed(2)} L`;
  } else {
    return `₹${value.toLocaleString('en-IN')}`;
  }
};

// utils/formatters/number.ts
export const formatNumber = (
  value: number,
  decimals: number = 2
): string => {
  return new Intl.NumberFormat('en-IN', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
};

export const formatQuantity = (qty: number): string => {
  if (qty >= 10000000) {
    return `${(qty / 10000000).toFixed(2)} Cr`;
  } else if (qty >= 100000) {
    return `${(qty / 100000).toFixed(2)} L`;
  } else if (qty >= 1000) {
    return `${(qty / 1000).toFixed(2)}K`;
  } else {
    return qty.toString();
  }
};

// utils/formatters/percentage.ts
export const formatPercentage = (
  value: number,
  showSign: boolean = true
): string => {
  const formatted = `${Math.abs(value).toFixed(2)}%`;

  if (showSign) {
    return value >= 0 ? `+${formatted}` : `-${formatted}`;
  }

  return formatted;
};

// utils/formatters/date.ts
import { format, formatDistanceToNow, isToday, isYesterday } from 'date-fns';
import { tz } from '@date-fns/tz';

const IST = 'Asia/Kolkata';

export const formatDate = (date: Date | string, formatStr: string = 'dd MMM yyyy'): string => {
  return format(new Date(date), formatStr, { timeZone: IST });
};

export const formatTime = (date: Date | string, formatStr: string = 'HH:mm:ss'): string => {
  return format(new Date(date), formatStr, { timeZone: IST });
};

export const formatDateTime = (date: Date | string): string => {
  return format(new Date(date), 'dd MMM yyyy, HH:mm:ss', { timeZone: IST });
};

export const formatRelativeTime = (date: Date | string): string => {
  return formatDistanceToNow(new Date(date), {
    addSuffix: true,
    timeZone: IST,
  });
};

export const formatTradeTime = (date: Date | string): string => {
  const d = new Date(date);
  if (isToday(d, { timeZone: IST })) {
    return formatTime(d, 'HH:mm');
  } else if (isYesterday(d, { timeZone: IST })) {
    return 'Yesterday';
  } else {
    return formatDate(d, 'dd MMM');
  }
};

// utils/formatters/index.ts
export * from './currency';
export * from './number';
export * from './percentage';
export * from './date';
```

### 14.2 Validators

```typescript
// utils/validators/order.validator.ts
import { z } from 'zod';
import { OrderType, OrderSide, ProductType } from '@/types/trading.types';

export const orderSchema = z.object({
  instrument: z.string().min(1, 'Instrument is required'),
  type: z.enum(['MARKET', 'LIMIT', 'SL', 'SL-M'] as const),
  side: z.enum(['BUY', 'SELL'] as const),
  quantity: z.number().positive('Quantity must be positive'),
  price: z.number().positive().optional(),
  triggerPrice: z.number().positive().optional(),
  product: z.enum(['INTRADAY', 'CNC', 'MARGIN'] as const),
  strategy: z.string().optional(),
}).refine((data) => {
  // Validate price for limit orders
  if (data.type === 'LIMIT' || data.type === 'SL') {
    return data.price !== undefined && data.price > 0;
  }
  return true;
}, {
  message: 'Price is required for LIMIT and SL orders',
  path: ['price'],
}).refine((data) => {
  // Validate trigger price for SL orders
  if (data.type === 'SL' || data.type === 'SL-M') {
    return data.triggerPrice !== undefined && data.triggerPrice > 0;
  }
  return true;
}, {
  message: 'Trigger price is required for SL and SL-M orders',
  path: ['triggerPrice'],
});

export const validateOrder = (data: any) => {
  return orderSchema.safeParse(data);
};

// utils/validators/strategy.validator.ts
export const strategySchema = z.object({
  name: z.string().min(3, 'Name must be at least 3 characters'),
  description: z.string().optional(),
  type: z.enum(['VISUAL', 'CODE'] as const),
  code: z.string().optional(),
  language: z.enum(['RUBY', 'PYTHON', 'JAVASCRIPT'] as const).optional(),
  parameters: z.record(z.any()),
  instruments: z.array(z.string()).min(1, 'At least one instrument is required'),
  timeframe: z.string().min(1, 'Timeframe is required'),
});

export const validateStrategy = (data: any) => {
  return strategySchema.safeParse(data);
};

// utils/validators/risk.validator.ts
export const riskLimitsSchema = z.object({
  maxRiskPerTrade: z.number().min(0).max(100),
  maxDailyLoss: z.number().min(0).max(100),
  maxOpenPositions: z.number().int().positive(),
  maxExposurePerSegment: z.number().min(0).max(100),
  stopLossBuffer: z.number().min(0),
  cooldownAfterStopLoss: z.number().int().nonnegative(),
});

export const validateRiskLimits = (data: any) => {
  return riskLimitsSchema.safeParse(data);
};

// utils/validators/index.ts
export * from './order.validator';
export * from './strategy.validator';
export * from './risk.validator';
```

### 14.3 Calculators

```typescript
// utils/calculators/pnl.calculator.ts
export const calculateUnrealizedPnL = (
  entryPrice: number,
  currentPrice: number,
  quantity: number,
  side: 'BUY' | 'SELL'
): number => {
  const priceDiff = currentPrice - entryPrice;
  const multiplier = side === 'BUY' ? 1 : -1;
  return priceDiff * quantity * multiplier;
};

export const calculatePnLPercent = (
  entryPrice: number,
  exitPrice: number,
  side: 'BUY' | 'SELL'
): number => {
  const priceDiff = exitPrice - entryPrice;
  const multiplier = side === 'BUY' ? 1 : -1;
  return (priceDiff / entryPrice) * 100 * multiplier;
};

export const calculateTotalPnL = (positions: any[]): {
  unrealized: number;
  realized: number;
  total: number;
} => {
  const unrealized = positions
    .filter(p => p.status === 'OPEN')
    .reduce((sum, p) => sum + p.unrealizedPnL, 0);

  const realized = positions
    .filter(p => p.status === 'CLOSED')
    .reduce((sum, p) => sum + p.realizedPnL, 0);

  return {
    unrealized,
    realized,
    total: unrealized + realized,
  };
};

// utils/calculators/margin.calculator.ts
export const calculateMarginRequired = (
  price: number,
  quantity: number,
  product: 'INTRADAY' | 'CNC' | 'MARGIN',
  segment: 'NFO' | 'BFO'
): number => {
  const totalValue = price * quantity;

  switch (product) {
    case 'INTRADAY':
      return totalValue * 0.2; // 20% margin for intraday
    case 'MARGIN':
      return totalValue * 0.5; // 50% margin for margin trading
    case 'CNC':
    default:
      return totalValue; // Full amount for CNC
  }
};

export const calculateBuyingPower = (
  availableFunds: number,
  product: 'INTRADAY' | 'CNC' | 'MARGIN'
): number => {
  switch (product) {
    case 'INTRADAY':
      return availableFunds * 5; // 5x leverage
    case 'MARGIN':
      return availableFunds * 2; // 2x leverage
    case 'CNC':
    default:
      return availableFunds; // No leverage
  }
};

// utils/calculators/risk.calculator.ts
export const calculatePositionSize = (
  capital: number,
  riskPercent: number,
  entryPrice: number,
  stopLossPrice: number
): number => {
  const riskAmount = capital * (riskPercent / 100);
  const riskPerShare = Math.abs(entryPrice - stopLossPrice);
  return Math.floor(riskAmount / riskPerShare);
};

export const calculateRiskRewardRatio = (
  entryPrice: number,
  targetPrice: number,
  stopLossPrice: number,
  side: 'BUY' | 'SELL'
): number => {
  const reward = Math.abs(targetPrice - entryPrice);
  const risk = Math.abs(entryPrice - stopLossPrice);
  return reward / risk;
};

// utils/calculators/index.ts
export * from './pnl.calculator';
export * from './margin.calculator';
export * from './risk.calculator';
```

---

## 15. PERFORMANCE OPTIMIZATION

### 15.1 Code Splitting & Lazy Loading

```typescript
// app/(dashboard)/strategies/creator/page.tsx
import dynamic from 'next/dynamic';

const StrategyCreator = dynamic(
  () => import('@/features/strategies/components/StrategyCreator'),
  {
    loading: () => <LoadingScreen />,
    ssr: false,
  }
);

export default function StrategyCreatorPage() {
  return <StrategyCreator />;
}

// components/charts/CandlestickChart/lazy.ts
import dynamic from 'next/dynamic';

export const LazyCandlestickChart = dynamic(
  () => import('./CandlestickChart').then(mod => mod.CandlestickChart),
  {
    loading: () => <ChartSkeleton />,
    ssr: false,
  }
);
```

### 15.2 Memoization

```typescript
// components/trading/OptionChain/OptionChain.tsx
export const OptionChain: React.FC<OptionChainProps> = React.memo(({
  underlying,
  spotPrice,
  expiry,
  strikes,
  view,
  onStrikeClick,
  loading = false
}) => {
  const atmStrike = useMemo(
    () => findATMStrike(strikes.map(s => s.strike), spotPrice),
    [strikes, spotPrice]
  );

  const columns = useMemo(() => {
    const baseColumns = [
      { key: 'callOi', label: 'OI', align: 'right' },
      { key: 'callChangeOi', label: 'Chg in OI', align: 'right' },
      { key: 'callVolume', label: 'Volume', align: 'right' },
      { key: 'callLtp', label: 'LTP', align: 'right' },
      { key: 'callChg', label: 'Chg %', align: 'right' },
    ];

    if (view === 'Greeks') {
      return [
        ...baseColumns,
        { key: 'callIv', label: 'IV', align: 'right' },
        { key: 'callDelta', label: 'Delta', align: 'right' },
        { key: 'callGamma', label: 'Gamma', align: 'right' },
        { key: 'callTheta', label: 'Theta', align: 'right' },
        { key: 'callVega', label: 'Vega', align: 'right' },
      ];
    }

    return baseColumns;
  }, [view]);

  // ... rest of component

}, (prevProps, nextProps) => {
  // Custom comparison function
  return (
    prevProps.spotPrice === nextProps.spotPrice &&
    prevProps.expiry === nextProps.expiry &&
    prevProps.view === nextProps.view &&
    prevProps.loading === nextProps.loading &&
    prevProps.strikes.length === nextProps.strikes.length
  );
});
```

### 15.3 Virtual Scrolling

```typescript
// components/ui/VirtualTable/VirtualTable.tsx
import { FixedSizeList as List } from 'react-window';

interface VirtualTableProps<T> {
  data: T[];
  columns: ColumnDef<T>[];
  rowHeight?: number;
  overscanCount?: number;
}

export const VirtualTable = <T,>({
  data,
  columns,
  rowHeight = 48,
  overscanCount = 5,
}: VirtualTableProps<T>) => {
  const Row = ({ index, style }: { index: number; style: React.CSSProperties }) => {
    const item = data[index];

    return (
      <div style={style} className="border-b border-gray-800">
        {columns.map(column => (
          <div key={column.key} className="px-4 py-2">
            {column.cell ? column.cell(item) : item[column.key as keyof T]}
          </div>
        ))}
      </div>
    );
  };

  return (
    <List
      height={600}
      itemCount={data.length}
      itemSize={rowHeight}
      overscanCount={overscanCount}
      width="100%"
    >
      {Row}
    </List>
  );
};
```

---

## 16. TESTING STRATEGY

### 16.1 Unit Tests

```typescript
// components/ui/Button/Button.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import { Button } from './Button';

describe('Button', () => {
  it('renders children correctly', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByRole('button')).toHaveTextContent('Click me');
  });

  it('handles click events', async () => {
    const handleClick = vi.fn();
    render(<Button onClick={handleClick}>Click me</Button>);

    await userEvent.click(screen.getByRole('button'));
    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it('applies correct variant classes', () => {
    const { container } = render(<Button variant="destructive">Delete</Button>);
    expect(container.firstChild).toHaveClass('bg-red-600');
  });

  it('disables button when loading', () => {
    render(<Button loading>Loading</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});

// utils/formatters/currency.test.ts
import { describe, it, expect } from 'vitest';
import { formatCurrency, formatLakhsCrores } from './currency';

describe('Currency Formatters', () => {
  describe('formatCurrency', () => {
    it('formats INR correctly', () => {
      expect(formatCurrency(1234567.89)).toBe('₹12,34,567.89');
    });

    it('handles negative values', () => {
      expect(formatCurrency(-1000)).toBe('-₹1,000.00');
    });
  });

  describe('formatLakhsCrores', () => {
    it('formats crores', () => {
      expect(formatLakhsCrores(15000000)).toBe('₹1.50 Cr');
    });

    it('formats lakhs', () => {
      expect(formatLakhsCrores(250000)).toBe('₹2.50 L');
    });

    it('formats thousands', () => {
      expect(formatLakhsCrores(5000)).toBe('₹5,000');
    });
  });
});
```

### 16.2 Integration Tests

```typescript
// tests/integration/orders.test.tsx
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { describe, it, expect, vi } from 'vitest';
import { OrdersPage } from '@/app/(dashboard)/orders/page';
import { tradingService } from '@/services/trading.service';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: false },
  },
});

describe('Orders Page', () => {
  it('fetches and displays orders', async () => {
    const mockOrders = [
      { id: '1', instrument: 'NIFTY', status: 'FILLED', quantity: 75 },
      { id: '2', instrument: 'BANKNIFTY', status: 'OPEN', quantity: 50 },
    ];

    vi.spyOn(tradingService, 'getOrders').mockResolvedValue(mockOrders);

    render(
      <QueryClientProvider client={queryClient}>
        <OrdersPage />
      </QueryClientProvider>
    );

    await waitFor(() => {
      expect(screen.getByText('NIFTY')).toBeInTheDocument();
      expect(screen.getByText('BANKNIFTY')).toBeInTheDocument();
    });
  });
});
```

### 16.3 E2E Tests

```typescript
// tests/e2e/trading-flow.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Trading Flow', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
    await page.fill('input[name="email"]', 'test@example.com');
    await page.fill('input[name="password"]', 'password123');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
  });

  test('places a market order', async ({ page }) => {
    // Navigate to market watch
    await page.click('text=Market Watch');
    await page.waitForURL('/market-watch');

    // Select NIFTY
    await page.click('text=NIFTY 50');

    // Open order ticket
    await page.click('button:has-text("BUY")');

    // Fill order details
    await page.selectOption('select[name="orderType"]', 'MARKET');
    await page.fill('input[name="quantity"]', '75');

    // Place order
    await page.click('button:has-text("Place Order")');

    // Verify order confirmation
    await expect(page.locator('text=Order placed successfully')).toBeVisible();

    // Navigate to orders page
    await page.click('text=Orders');
    await page.waitForURL('/orders');

    // Verify order appears in list
    await expect(page.locator('text=NIFTY')).toBeVisible();
  });

  test('views positions and P&L', async ({ page }) => {
    await page.goto('/positions');

    // Check KPI cards
    await expect(page.locator('text=Net P&L')).toBeVisible();
    await expect(page.locator('text=Unrealized P&L')).toBeVisible();

    // Check positions table
    const positionsTable = page.locator('table');
    await expect(positionsTable).toBeVisible();
  });
});
```

---

## 📝 APPENDIX

### A. Environment Variables

```env
# .env.local
NEXT_PUBLIC_API_URL=https://api.dhan.co/v2
NEXT_PUBLIC_WS_URL=wss://api.dhan.co/v2/ws
NEXT_PUBLIC_DHAN_CLIENT_ID=your-client-id

# Auth
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=your-secret-key

# Feature Flags
NEXT_PUBLIC_ENABLE_WEBSOCKET=true
NEXT_PUBLIC_ENABLE_BACKTESTING=true
NEXT_PUBLIC_ENABLE_STRATEGY_CREATOR=true

# Performance
NEXT_PUBLIC_ENABLE_ANALYTICS=true
NEXT_PUBLIC_SENTRY_DSN=your-sentry-dsn
```

### B. Build & Deployment

```bash
# Development
npm run dev

# Build
npm run build

# Production
npm run start

# Test
npm run test          # Unit tests
npm run test:e2e      # E2E tests
npm run test:coverage # Coverage report

# Lint & Type Check
npm run lint
npm run type-check
```

---

**END OF TECHNICAL DESIGN DOCUMENT**

This TDD provides a comprehensive blueprint for building the Algo Scalper frontend. It covers architecture, components, state management, API integration, testing, and deployment strategies following modern React/Next.js best practices.

Would you like me to elaborate on any specific section or provide additional implementation details?