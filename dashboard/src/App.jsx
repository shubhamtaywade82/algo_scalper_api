import { Router, Route } from '@solidjs/router'
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

// New TDD routes — all backends implemented
const MarketWatch = lazy(() => import('./views/MarketWatch'))
const Positions = lazy(() => import('./views/Positions'))
const Holdings = lazy(() => import('./views/Holdings'))
const Funds = lazy(() => import('./views/Funds'))
const Reports = lazy(() => import('./views/Reports'))
const Alerts = lazy(() => import('./views/Alerts'))
const Scheduler = lazy(() => import('./views/Scheduler'))
const Logs = lazy(() => import('./views/Logs'))

// Auth routes
const Login = lazy(() => import('./views/Login'))
const Register = lazy(() => import('./views/Register'))
import AuthGuard from './components/auth/AuthGuard'

function Protected(props) {
  return <AuthGuard>{props.children}</AuthGuard>
}

function AppShell(props) {
  const {
    open, closed,
    connected: positionsConnected,
    isStale: positionsStale,
    lastMessageAt: positionsLastMessageAt,
    fetchPositions
  } = usePositions()

  const {
    mode, connected, isStale: dashboardStale, stats, balance, indices, subscribedIndices, system,
    publicIpv4, publicIpv6, registeredIps, circuitBreaker,
    lastUpdated, recentSignals, config
  } = useDashboard(() => fetchPositions())

  const { sidebarCollapsed, toggleSidebar } = useUIStore()

  async function closePositionAndRefresh(positionId) {
    const result = await closeOpenPosition(positionId)
    if (result?.ok) refreshDashboard()
    return result
  }

  const ctx = {
    mode, connected, dashboardStale, stats, balance, indices, subscribedIndices, system,
    publicIpv4, publicIpv6, registeredIps, circuitBreaker,
    lastUpdated, recentSignals, config,
    open, closed,
    positionsConnected, positionsStale, positionsLastMessageAt,
    fetchPositions
  }

  return (
    <DashboardContext.Provider value={ctx}>
      <div class="min-h-screen bg-transparent text-gray-100 font-sans selection:bg-primary-500/30">
        <Toaster position="bottom-right" gutter={8} toastOptions={{ className: '!bg-gray-800 !text-gray-100 !border !border-white/10 !rounded-xl !shadow-2xl' }} />
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
        <div class="flex">
          <Sidebar collapsed={sidebarCollapsed()} />
          <main class={`flex-1 transition-all duration-300 pt-1 pb-20 ${sidebarCollapsed() ? 'ml-16' : 'ml-56'}`}>
            <div class="px-8 pt-3 pb-6 w-full">
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
      {/* Auth pages — own layout, no header chrome */}
      <Route path="/login" component={Login} />
      <Route path="/register" component={Register} />

      {/* Protected app shell */}
      <Route component={Protected}>
        <Route component={AppShell}>
          <Route path="/" component={Dashboard} />
          <Route path="/strategies/creator" component={StrategyCreator} />
          <Route path="/strategies/:id" component={StrategyCreator} />
          <Route path="/strategies" component={Strategies} />
          <Route path="/alpha" component={Alpha} />
          <Route path="/signals" component={Signals} />
          <Route path="/option-scalper" component={OptionScalper} />
          <Route path="/option-chain" component={OptionChain} />
          <Route path="/analysis" component={Analysis} />
          <Route path="/ledger" component={Ledger} />
          <Route path="/settings" component={Settings} />
          <Route path="/backtester" component={Backtester} />
          <Route path="/replay" component={Replay} />
          {/* New routes from TDD layout */}
          <Route path="/market-watch" component={MarketWatch} />
          <Route path="/positions" component={Positions} />
          <Route path="/holdings" component={Holdings} />
          <Route path="/funds" component={Funds} />
          <Route path="/reports" component={Reports} />
          <Route path="/alerts" component={Alerts} />
          <Route path="/scheduler" component={Scheduler} />
          <Route path="/logs" component={Logs} />
        </Route>
      </Route>

      {/* Fullscreen — own layout, no Header/footer chrome */}
      <Route path="/charts" component={Charts} />
      <Route path="/trail-engine" component={TrailEngine} />
    </Router>
  )
}
