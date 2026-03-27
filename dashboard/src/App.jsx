import { Router, Route } from '@solidjs/router'
import { Show, lazy } from 'solid-js'
import { DashboardContext } from './context/DashboardContext'
import { useDashboard } from './stores/useDashboard'
import { usePositions } from './stores/usePositions'
import Header from './components/Header'
import './style.css'

const Dashboard = lazy(() => import('./views/Dashboard'))
const Strategies = lazy(() => import('./views/Strategies'))
const Signals = lazy(() => import('./views/Signals'))
const Analysis = lazy(() => import('./views/Analysis'))
const Settings = lazy(() => import('./views/Settings'))

function AppShell(props) {
  const {
    open, closed,
    connected: positionsConnected,
    isStale: positionsStale,
    lastMessageAt: positionsLastMessageAt,
    fetchPositions
  } = usePositions()

  const {
    mode, connected, stats, balance, indices, system,
    publicIpv4, publicIpv6, registeredIps, circuitBreaker,
    lastUpdated, recentSignals, config
  } = useDashboard(() => fetchPositions())

  const ctx = {
    mode, connected, stats, balance, indices, system,
    publicIpv4, publicIpv6, registeredIps, circuitBreaker,
    lastUpdated, recentSignals, config,
    open, closed,
    positionsConnected, positionsStale, positionsLastMessageAt,
    fetchPositions
  }

  return (
    <DashboardContext.Provider value={ctx}>
      <div class="min-h-screen bg-transparent text-gray-100 font-sans selection:bg-primary-500/30">
        <Header
          mode={mode()}
          indices={indices()}
          system={system()}
          connected={connected()}
        />
        <main class="p-6 max-w-screen-2xl mx-auto pb-20">
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
        </main>
      </div>
    </DashboardContext.Provider>
  )
}

export default function App() {
  return (
    <Router root={AppShell}>
      <Route path="/" component={Dashboard} />
      <Route path="/strategies" component={Strategies} />
      <Route path="/signals" component={Signals} />
      <Route path="/analysis" component={Analysis} />
      <Route path="/settings" component={Settings} />
    </Router>
  )
}
