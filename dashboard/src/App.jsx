import { Router, Route, Navigate } from '@solidjs/router'
import { Show, lazy } from 'solid-js'
import { DashboardContext } from './context/DashboardContext'
import { Toaster } from 'solid-toast'
import { useDashboard } from './stores/useDashboard'
import { usePositions } from './stores/usePositions'
import { useUIStore } from './stores/ui.store'
import Header from './components/Header'
import Sidebar from './components/layout/Sidebar'
import './style.css'

const Dashboard = lazy(() => import('./views/Dashboard'))
const Strategies = lazy(() => import('./views/Strategies'))
const StrategyCreator = lazy(() => import('./views/StrategyCreator'))
const Signals = lazy(() => import('./views/Signals'))
const Analysis = lazy(() => import('./views/Analysis'))
const Settings = lazy(() => import('./views/Settings'))
const Ledger = lazy(() => import('./views/Ledger'))
const TrailEngine = lazy(() => import('./views/TrailEngine.jsx'))
const OptionScalper = lazy(() => import('./views/OptionScalper'))
const OptionChain = lazy(() => import('./views/OptionChain'))
const Backtester = lazy(() => import('./views/Backtester'))
const Replay = lazy(() => import('./views/Replay'))
const Alpha = lazy(() => import('./views/Alpha'))
const Charts = lazy(() => import('./views/Charts'))

// New TDD routes — all backends implemented
const MarketWatch = lazy(() => import('./views/MarketWatch'))
const Positions = lazy(() => import('./views/Positions'))
const Holdings = lazy(() => import('./views/Holdings'))
const Funds = lazy(() => import('./views/Funds'))
const Reports = lazy(() => import('./views/Reports'))
const MarketBrief = lazy(() => import('./views/MarketBrief'))
const Alerts = lazy(() => import('./views/Alerts'))
const Scheduler = lazy(() => import('./views/Scheduler'))
const Logs = lazy(() => import('./views/Logs'))
const Portfolio = lazy(() => import('./views/Portfolio'))
const System = lazy(() => import('./views/System'))
const StrategiesHub = lazy(() => import('./views/StrategiesHub'))

function AppShell(props) {
  const {
    open, closed,
    connected: positionsConnected,
    isStale: positionsStale,
    lastMessageAt: positionsLastMessageAt,
    fetchPositions,
    closeOpenPosition,
    closingPositionId
  } = usePositions()

  const {
    mode, connected, isStale: dashboardStale, stats, balance, indices, subscribedIndices, system,
    publicIpv4, publicIpv6, registeredIps, circuitBreaker,
    lastUpdated, recentSignals, strategiesSummary, config,
    marketStatus
  } = useDashboard(() => fetchPositions())

  const { sidebarCollapsed, toggleSidebar } = useUIStore()

  const ctx = {
    mode, connected, dashboardStale, stats, balance, indices, subscribedIndices, system,
    publicIpv4, publicIpv6, registeredIps, circuitBreaker,
    lastUpdated, recentSignals, strategiesSummary, config,
    open, closed,
    positionsConnected, positionsStale, positionsLastMessageAt,
    fetchPositions,
    closeOpenPosition,
    closingPositionId,
    marketStatus
  }


  return (
    <DashboardContext.Provider value={ctx}>
      <div class="min-h-screen bg-transparent text-gray-100 font-sans selection:bg-primary-500/30 flex">
        <Toaster position="bottom-right" gutter={8} toastOptions={{ className: '!bg-gray-800 !text-gray-100 !border !border-white/10 !rounded-xl !shadow-2xl' }} />
        <Sidebar collapsed={sidebarCollapsed()} />
        <div class="flex-1 flex flex-col min-w-0">
          <Header
            mode={mode()}
            indices={indices()}
            subscribedIndices={subscribedIndices()}
            system={system()}
            connected={connected()}
            isStale={dashboardStale()}
            marketStatus={marketStatus()}
            onToggleSidebar={toggleSidebar}
            sidebarCollapsed={sidebarCollapsed()}
          />
          <main class="flex-1 pt-1 pb-20">
            <div class="px-3 md:px-8 pt-3 pb-6 w-full">
              {props.children}

              <Show when={lastUpdated()}>
                <footer class="flex items-center justify-center gap-6 pt-20 pb-10 border-t border-white/5 mt-10">
                  <div class="flex items-center gap-2.5 px-5 py-2.5 rounded-full glass border border-white/5 text-[10px] text-gray-500 font-black tracking-[0.2em] uppercase">
                    <span class="w-1.5 h-1.5 rounded-full bg-primary-500 shadow-[0_0_8px_rgba(59,130,246,0.5)] animate-pulse"></span>
                    Vault Sync Active
                  </div>
                  <div class="text-[10px] text-gray-600 font-black uppercase tracking-[0.2em]">
                    Refreshed: {new Date(lastUpdated()).toLocaleTimeString('en-IN')}
                  </div>
                </footer>
              </Show>
            </div>
          </main>
        </div>
      </div>
    </DashboardContext.Provider>
  )
}

export default function App() {
  return (
    <Router>
      {/* App shell */}
      <Route component={AppShell}>
        <Route path="/" component={Dashboard} />
        <Route path="/strategies/creator" component={StrategyCreator} />
        <Route path="/strategies/:id" component={StrategyCreator} />
        <Route path="/strategies" component={() => <StrategiesHub defaultTab="strategies" />} />
        <Route path="/alpha" component={() => <StrategiesHub defaultTab="alpha" />} />
        <Route path="/signals" component={() => <StrategiesHub defaultTab="signals" />} />
        <Route path="/backtester" component={() => <StrategiesHub defaultTab="backtester" />} />
        <Route path="/replay" component={() => <StrategiesHub defaultTab="replay" />} />
        <Route path="/option-scalper" component={() => <Navigate href="/option-chain" />} />
        <Route path="/option-chain" component={OptionChain} />
        <Route path="/analysis" component={Analysis} />
        <Route path="/portfolio" component={Portfolio} />
        <Route path="/positions" component={() => <Portfolio defaultTab="positions" />} />
        <Route path="/ledger" component={() => <Portfolio defaultTab="orders" />} />
        <Route path="/orders" component={() => <Portfolio defaultTab="orders" />} />
        <Route path="/holdings" component={() => <Portfolio defaultTab="holdings" />} />
        <Route path="/funds" component={() => <Portfolio defaultTab="funds" />} />
        <Route path="/market-watch" component={MarketWatch} />
        <Route path="/reports" component={Reports} />
        <Route path="/market-mood" component={MarketBrief} />
        <Route path="/market-brief" component={() => <Navigate href="/market-mood" />} />
        <Route path="/system" component={System} />
        <Route path="/settings" component={() => <System defaultTab="settings" />} />
        <Route path="/scheduler" component={() => <System defaultTab="scheduler" />} />
        <Route path="/logs" component={() => <System defaultTab="logs" />} />
        <Route path="/alerts" component={() => <System defaultTab="alerts" />} />
        <Route path="*" component={() => <Navigate href="/" />} />
      </Route>

      {/* Fullscreen — own layout, no Header/footer chrome */}
      <Route path="/charts" component={Charts} />
      <Route path="/trail-engine" component={TrailEngine} />
    </Router>
  )
}
