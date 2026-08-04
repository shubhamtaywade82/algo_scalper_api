import { createMemo } from 'solid-js'
import { Show } from 'solid-js'
import { A, useLocation } from '@solidjs/router'
import { useDashboardContext } from '../context/DashboardContext'
import { useFlash } from '../stores/useFlash'
import { confluenceLtfCompact, expiryBadgeMeta, subscribedRowByKey } from '../lib/expiryBadge'
import AnimatedNumber from './AnimatedNumber'

function formatNextDay(iso) {
  if (!iso) return ''
  try {
    const d = new Date(iso + 'T00:00:00+05:30')
    return d.toLocaleDateString('en-IN', { weekday: 'short', month: 'short', day: 'numeric' })
  } catch { return iso }
}

function MarketStatusBanner(props) {
  const ms = () => props.status
  if (!ms()) return null

  const bannerMeta = createMemo(() => {
    const s = ms()
    if (!s) return null

    // Market is open
    if (s.market_open) {
      return {
        icon: '🟢',
        text: 'MARKET OPEN',
        sub: s.session?.reason || '',
        bgClass: 'bg-emerald-500/8 border-emerald-500/20',
        textClass: 'text-emerald-400',
        dotClass: 'bg-emerald-400',
        pulse: true
      }
    }

    // Holiday
    if (!s.is_trading_day && s.holiday_name) {
      return {
        icon: '🏛️',
        text: `MARKET HOLIDAY — ${s.holiday_name}`,
        sub: `Next session: ${formatNextDay(s.next_trading_day)}`,
        bgClass: 'bg-amber-500/8 border-amber-500/20',
        textClass: 'text-amber-400',
        dotClass: 'bg-amber-400',
        pulse: false
      }
    }

    // Weekend
    if (!s.is_trading_day) {
      return {
        icon: '📅',
        text: 'WEEKEND',
        sub: `Next session: ${formatNextDay(s.next_trading_day)}`,
        bgClass: 'bg-gray-500/8 border-gray-500/20',
        textClass: 'text-gray-400',
        dotClass: 'bg-gray-500',
        pulse: false
      }
    }

    // Trading day but market closed — check session reason
    const reason = s.session?.reason || ''
    if (reason.includes('before')) {
      return {
        icon: '⏳',
        text: 'PRE-MARKET',
        sub: 'Opens at 09:20 IST',
        bgClass: 'bg-blue-500/8 border-blue-500/20',
        textClass: 'text-blue-400',
        dotClass: 'bg-blue-400',
        pulse: true
      }
    }

    // Post-market
    return {
      icon: '🔒',
      text: 'MARKET CLOSED',
      sub: `Next session: ${formatNextDay(s.next_trading_day)}`,
      bgClass: 'bg-gray-500/8 border-gray-500/20',
      textClass: 'text-gray-400',
      dotClass: 'bg-gray-500',
      pulse: false
    }
  })

  return (
    <Show when={bannerMeta() && !bannerMeta().text?.includes('OPEN')}>
      <div
        class={`flex items-center justify-center gap-3 px-4 py-2 border-b transition-all duration-500 ${bannerMeta().bgClass}`}
        id="market-status-banner"
      >
        <span class="text-sm">{bannerMeta().icon}</span>
        <div class="flex items-center gap-2">
          <span class={`relative flex h-2 w-2`}>
            <Show when={bannerMeta().pulse}>
              <span class={`animate-ping absolute inline-flex h-full w-full rounded-full ${bannerMeta().dotClass} opacity-75`}></span>
            </Show>
            <span class={`relative inline-flex rounded-full h-2 w-2 ${bannerMeta().dotClass}`}></span>
          </span>
          <span class={`text-[10px] font-black uppercase tracking-[0.15em] ${bannerMeta().textClass}`}>
            {bannerMeta().text}
          </span>
        </div>
        <Show when={bannerMeta().sub}>
          <span class="text-[9px] font-bold text-gray-500 tracking-wide">
            · {bannerMeta().sub}
          </span>
        </Show>
      </div>
    </Show>
  )
}

function SidebarToggle(props) {
  return (
    <button
      onClick={props.onToggle}
      class="p-2 rounded-lg text-gray-500 hover:text-gray-300 hover:bg-white/[0.05] transition-all duration-200 mr-2"
      title={props.collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
    >
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path d="M9 18l6-6-6-6" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </button>
  )
}

export default function Header(props) {
  const OptionsBuyingStatePills = (p) => {
    const ob = () => props.optionsBuying?.[p.indexKey] || {}
    return (
      <div class="flex items-center gap-1 mt-0.5">
        <Show when={ob().regime && ob().regime !== 'UNKNOWN' && ob().regime !== 'RANGING'}>
          <span class="text-[6px] font-black uppercase tracking-tight px-1 py-0.5 rounded border leading-none bg-blue-500/10 text-blue-400 border-blue-500/20">
            {ob().regime}
          </span>
        </Show>
        <Show when={ob().breakout_ready}>
          <span class={`text-[6px] font-black uppercase tracking-tight px-1 py-0.5 rounded border leading-none ${ob().direction === 'BULLISH' ? 'bg-green-500/10 text-green-400 border-green-500/20' : 'bg-red-500/10 text-red-400 border-red-500/20'}`}>
            ARMED: {ob().direction}
          </span>
        </Show>
      </div>
    )
  }

  const { publicIpv4, publicIpv6, registeredIps, stats } = useDashboardContext()

  const openPnl = () => stats()?.unrealized_pnl_rupees ?? 0
  const openPnlPct = () => stats()?.unrealized_pnl_pct ?? 0
  const realizedPnl = () => stats()?.realized_pnl_rupees ?? 0
  const realizedPnlPct = () => stats()?.realized_pnl_pct ?? 0

  const openPnlColorClass = createMemo(() => {
    const val = Number(openPnl() || 0)
    if (val > 0) return 'border-emerald-500/10 hover:border-emerald-500/20 hover:shadow-[0_0_12px_rgba(16,185,129,0.08)] bg-emerald-500/[0.02]'
    if (val < 0) return 'border-rose-500/10 hover:border-rose-500/20 hover:shadow-[0_0_12px_rgba(239,68,68,0.08)] bg-rose-500/[0.02]'
    return 'border-white/5 hover:border-white/10'
  })

  const realizedPnlColorClass = createMemo(() => {
    const val = Number(realizedPnl() || 0)
    if (val > 0) return 'border-emerald-500/10 hover:border-emerald-500/20 hover:shadow-[0_0_12px_rgba(16,185,129,0.08)] bg-emerald-500/[0.02]'
    if (val < 0) return 'border-rose-500/10 hover:border-rose-500/20 hover:shadow-[0_0_12px_rgba(239,68,68,0.08)] bg-rose-500/[0.02]'
    return 'border-white/5 hover:border-white/10'
  })


  const isIpVerified = createMemo(() => {
    const ips = registeredIps()
    if (!ips) return false
    const registered = [ips.primary_ip, ips.secondary_ip].filter(Boolean)
    return registered.includes(publicIpv4()) || (publicIpv6() !== 'None' && registered.includes(publicIpv6()))
  })

  const niftyFlash = useFlash(() => props.indices?.nifty)
  const bankniftyFlash = useFlash(() => props.indices?.banknifty)
  const sensexFlash = useFlash(() => props.indices?.sensex)

  function expiryBlock(indexKey) {
    const row = subscribedRowByKey(props.subscribedIndices, indexKey)
    return expiryBadgeMeta(row)
  }

  const navLinkBase = 'px-3 py-1.5 rounded-lg text-[10px] font-black uppercase tracking-widest transition-all duration-300 hover:text-white flex items-center gap-1.5 group border border-transparent'
  const navLinkInactive = 'text-gray-500 hover:bg-white/[0.02]'
  const navLinkActive = 'bg-primary-500/10 text-primary-300 border-primary-500/25 shadow-[0_0_15px_rgba(59,130,246,0.15)]'
  const navLinkSettingsActive = 'bg-cyan-500/10 text-cyan-300 border-cyan-500/25 shadow-[0_0_15px_rgba(6,182,212,0.15)]'
  const navLinkLedgerActive = 'bg-violet-500/10 text-violet-300 border-violet-500/25 shadow-[0_0_15px_rgba(139,92,246,0.15)]'

  const location = useLocation()
  const pageTitle = createMemo(() => {
    const path = location.pathname
    if (path === '/') return 'Dashboard'
    const segment = path.split('/')[1] || ''
    if (!segment) return 'Dashboard'
    if (segment === 'option-scalper') return 'Option Scalper'
    return segment.charAt(0).toUpperCase() + segment.slice(1)
  })

  return (
    <div class="sticky top-0 z-50">
      <header class="relative glass border-b border-white/5 px-6 py-2.5 flex items-center justify-between gap-4">
        {/* Left Section: toggle + title & tickers */}
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <SidebarToggle onToggle={props.onToggleSidebar} collapsed={props.sidebarCollapsed} />
          <div class="flex flex-col shrink-0">
            <span class="text-[10px] font-black text-primary-400 tracking-[0.3em] uppercase">{props.mode} ENGINE</span>
            <span class="text-[10px] font-bold text-gray-500 tracking-widest mt-0.5 uppercase">Active Terminal</span>
          </div>

          <div class="hidden xl:flex items-center gap-2 border-l border-white/10 pl-3 min-w-0">
            {/* Nifty 50 Card */}
            <a
              href="/charts?symbol=NIFTY"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-3 bg-white/[0.02] border border-white/5 rounded-xl px-3 py-1.5 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[10px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Nifty 50</span>
                <span class={`text-[16px] font-black text-white text-data transition-all duration-300 rounded px-0.5 ${niftyFlash()}`}>
                  <AnimatedNumber value={props.indices?.nifty} decimals={2} nullDisplay="—" />
                </span>
              </div>
              <div class="flex flex-col items-end gap-0.5">
                {(() => {
                  const b = expiryBlock('NIFTY')
                  return (
                    <>
                      <span class={`text-[6px] font-black uppercase tracking-tight px-1 py-0.5 rounded border leading-none ${b.className}`}>
                        {b.text}
                      </span>
                      <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'NIFTY'))}>
                        <span
                          class="text-[5px] font-mono text-gray-500 leading-none tracking-tighter"
                          title="SMC Confluence LTF (Pine) — enable signals.enable_smc_confluence_digest"
                        >
                          {confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'NIFTY'))}
                        </span>
                      </Show>
                      <OptionsBuyingStatePills indexKey="nifty" />
                    </>
                  )
                })()}
              </div>
            </a>

            {/* Bank Nifty Card */}
            <a
              href="/charts?symbol=BANKNIFTY"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-3 bg-white/[0.02] border border-white/5 rounded-xl px-3 py-1.5 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[10px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Bank Nifty</span>
                <span class={`text-[16px] font-black text-white text-data transition-all duration-300 rounded px-0.5 ${bankniftyFlash()}`}>
                  <AnimatedNumber value={props.indices?.banknifty} decimals={2} nullDisplay="—" />
                </span>
              </div>
              <div class="flex flex-col items-end gap-0.5">
                {(() => {
                  const b = expiryBlock('BANKNIFTY')
                  return (
                    <>
                      <span class={`text-[6px] font-black uppercase tracking-tight px-1 py-0.5 rounded border leading-none ${b.className}`}>
                        {b.text}
                      </span>
                      <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'BANKNIFTY'))}>
                        <span
                          class="text-[5px] font-mono text-gray-500 leading-none tracking-tighter"
                          title="SMC Confluence LTF (Pine) — enable signals.enable_smc_confluence_digest"
                        >
                          {confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'BANKNIFTY'))}
                        </span>
                      </Show>
                      <OptionsBuyingStatePills indexKey="banknifty" />
                    </>
                  )
                })()}
              </div>
            </a>

            {/* Sensex Card */}
            <a
              href="/charts?symbol=SENSEX"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-3 bg-white/[0.02] border border-white/5 rounded-xl px-3 py-1.5 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[10px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Sensex</span>
                <span class={`text-[16px] font-black text-white text-data transition-all duration-300 rounded px-0.5 ${sensexFlash()}`}>
                  <AnimatedNumber value={props.indices?.sensex} decimals={2} nullDisplay="—" />
                </span>
              </div>
              <div class="flex flex-col items-end gap-0.5">
                {(() => {
                  const b = expiryBlock('SENSEX')
                  return (
                    <>
                      <span class={`text-[6px] font-black uppercase tracking-tight px-1 py-0.5 rounded border leading-none ${b.className}`}>
                        {b.text}
                      </span>
                      <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'SENSEX'))}>
                        <span
                          class="text-[5px] font-mono text-gray-500 leading-none tracking-tighter"
                          title="SMC Confluence LTF (Pine) — enable signals.enable_smc_confluence_digest"
                        >
                          {confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'SENSEX'))}
                        </span>
                      </Show>
                      <OptionsBuyingStatePills indexKey="sensex" />
                    </>
                  )
                })()}
              </div>
            </a>
          </div>

        </div>

        {/* Center Section: Centered Dynamic Page Title */}
        <div class="absolute left-1/2 -translate-x-1/2 flex flex-col items-center pointer-events-none">
          <span class="text-xs font-black text-white uppercase tracking-[0.25em]">{pageTitle()}</span>
          <span class="text-[7px] font-bold text-gray-500 tracking-widest uppercase mt-0.5">Real-time view</span>
        </div>

        {/* Right Section: System badges */}
        <div class="flex items-center gap-2.5 text-[9px] font-black tracking-wider flex-1 justify-end shrink-0">
          {/* P&L Header Widgets */}
          <div class="hidden lg:flex items-center gap-2 mr-2">
            {/* Open P&L Badge */}
            <div class={`flex items-center gap-2 px-3 py-1.5 rounded-full border transition-all duration-300 ${openPnlColorClass()}`}>
              <span class="text-[8px] font-black text-gray-500 uppercase tracking-wider">Open P&L</span>
              <span class="text-[10px] font-black">
                <AnimatedNumber value={openPnl()} currency decimals={0} showSign pnlColor />
              </span>
              <span class="text-[8px] font-bold">
                (<AnimatedNumber value={openPnlPct()} suffix="%" showSign pnlColor />)
              </span>
            </div>

            {/* Realized P&L Badge */}
            <div class={`flex items-center gap-2 px-3 py-1.5 rounded-full border transition-all duration-300 ${realizedPnlColorClass()}`}>
              <span class="text-[8px] font-black text-gray-500 uppercase tracking-wider">Realized P&L</span>
              <span class="text-[10px] font-black">
                <AnimatedNumber value={realizedPnl()} currency decimals={0} showSign pnlColor />
              </span>
              <span class="text-[8px] font-bold">
                (<AnimatedNumber value={realizedPnlPct()} suffix="%" showSign pnlColor />)
              </span>
            </div>
          </div>

          <div
            class={`flex items-center gap-2 px-3 py-1.5 rounded-full border bg-white/[0.01] transition-all duration-300 ${isIpVerified() ? 'border-emerald-500/10 hover:border-emerald-500/25 text-gray-500 hover:text-gray-300' : 'border-rose-500/10 hover:border-rose-500/25 text-rose-400'}`}
            title={isIpVerified() ? `Verified: ${publicIpv4()}` : `Not Registered: ${publicIpv4()}`}
          >
            <span class="relative flex h-1.5 w-1.5">
              <Show when={!isIpVerified()}>
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"></span>
              </Show>
              <span class={`relative inline-flex rounded-full h-1.5 w-1.5 ${isIpVerified() ? 'bg-emerald-400' : 'bg-rose-500'}`}></span>
            </span>
            <span>NET ID</span>
          </div>

          <div class={`flex items-center gap-2 px-3 py-1.5 rounded-full border bg-white/[0.01] transition-all duration-300 ${props.system?.ws_market_feed ? 'border-emerald-500/10 hover:border-emerald-500/25 text-gray-500 hover:text-gray-300' : 'border-gray-800 text-gray-600'}`}>
            <span class="relative flex h-1.5 w-1.5">
              <Show when={props.system?.ws_market_feed}>
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              </Show>
              <span class={`relative inline-flex rounded-full h-1.5 w-1.5 ${props.system?.ws_market_feed ? 'bg-emerald-400' : 'bg-gray-700'}`}></span>
            </span>
            <span>FEED</span>
          </div>

          <div class={`flex items-center gap-2 px-3 py-1.5 rounded-full border bg-white/[0.01] transition-all duration-300 ${props.system?.scheduler === 'running' ? 'border-emerald-500/10 hover:border-emerald-500/25 text-gray-500 hover:text-gray-300' : 'border-rose-500/10 hover:border-rose-500/25 text-rose-400'}`}>
            <span class="relative flex h-1.5 w-1.5">
              <Show when={props.system?.scheduler === 'running'}>
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              </Show>
              <span class={`relative inline-flex rounded-full h-1.5 w-1.5 ${props.system?.scheduler === 'running' ? 'bg-emerald-400' : 'bg-rose-500'}`}></span>
            </span>
            <span>ENGINE</span>
          </div>

          <div class={`flex items-center gap-2 px-3 py-1.5 rounded-full border bg-white/[0.01] transition-all duration-300 ${props.system?.pnl_updater_running ? 'border-emerald-500/10 hover:border-emerald-500/25 text-gray-500 hover:text-gray-300' : 'border-gray-800 text-gray-600'}`}>
            <span class="relative flex h-1.5 w-1.5">
              <Show when={props.system?.pnl_updater_running}>
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              </Show>
              <span class={`relative inline-flex rounded-full h-1.5 w-1.5 ${props.system?.pnl_updater_running ? 'bg-emerald-400' : 'bg-gray-700'}`}></span>
            </span>
            <span>PNL</span>
          </div>

          <div class={`flex items-center gap-2 px-4 py-1.5 rounded-full border transition-all duration-500 ${props.connected ? (props.isStale ? 'bg-amber-500/10 border-amber-500/25 text-amber-400 shadow-[0_0_15px_rgba(245,158,11,0.1)]' : 'bg-emerald-500/10 border-emerald-500/25 text-emerald-400 shadow-[0_0_15px_rgba(16,185,129,0.1)]') : 'bg-rose-500/10 border-rose-500/25 text-rose-400 shadow-[0_0_15px_rgba(239,68,68,0.1)]'}`}>
            <span class="relative flex h-1.5 w-1.5">
              <Show when={props.connected}>
                <span class={`animate-ping absolute inline-flex h-full w-full rounded-full opacity-75 ${props.isStale ? 'bg-amber-400' : 'bg-emerald-400'}`}></span>
              </Show>
              <span class={`relative inline-flex rounded-full h-1.5 w-1.5 ${props.connected ? (props.isStale ? 'bg-amber-400' : 'bg-emerald-400') : 'bg-rose-500'}`}></span>
            </span>
            <span class="font-black tracking-[0.1em]">
              {!props.connected ? 'OFFLINE' : (props.isStale ? 'STALE' : 'LIVE')}
            </span>
          </div>
        </div>
      </header>
      <MarketStatusBanner status={props.marketStatus} />
    </div>
  )
}

