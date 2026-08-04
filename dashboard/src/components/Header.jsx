import { createMemo } from 'solid-js'
import { Show } from 'solid-js'
import { A, useLocation } from '@solidjs/router'
import { useDashboardContext } from '../context/DashboardContext'
import { useFlash } from '../stores/useFlash'

function inr(val) {
  if (val == null) return '—'
  return Number(val).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
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

  const { publicIpv4, publicIpv6, registeredIps } = useDashboardContext()

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
            <span class="text-[8px] font-bold text-gray-500 tracking-widest mt-0.5 uppercase">Active Terminal</span>
          </div>

          <div class="hidden xl:flex items-center gap-2 border-l border-white/10 pl-3 min-w-0">
            {/* Nifty 50 Card */}
            <a
              href="/charts?symbol=NIFTY"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 bg-white/[0.02] border border-white/5 rounded-xl px-2.5 py-1 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[8px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Nifty 50</span>
                <span class={`text-[11px] font-black text-white text-data transition-all duration-300 rounded px-0.5 mt-0.5 ${niftyFlash()}`}>
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
              class="flex items-center gap-2 bg-white/[0.02] border border-white/5 rounded-xl px-2.5 py-1 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[8px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Bank Nifty</span>
                <span class={`text-[11px] font-black text-white text-data transition-all duration-300 rounded px-0.5 mt-0.5 ${bankniftyFlash()}`}>
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
              class="flex items-center gap-2 bg-white/[0.02] border border-white/5 rounded-xl px-2.5 py-1 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[8px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Sensex</span>
                <span class={`text-[11px] font-black text-white text-data transition-all duration-300 rounded px-0.5 mt-0.5 ${sensexFlash()}`}>
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
          </div>
          <div class="flex flex-col">
            <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Bank Nifty</span>
            <span class={`text-sm font-black text-white text-data transition-all duration-300 rounded px-1 ${bankniftyFlash()}`}>
              {inr(props.indices?.banknifty)}
            </span>
          </div>
          <div class="flex flex-col">
            <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Sensex</span>
            <span class={`text-sm font-black text-white text-data transition-all duration-300 rounded px-1 ${sensexFlash()}`}>
              {inr(props.indices?.sensex)}
            </span>
          </div>
        </div>
      </div>

      <nav class="absolute left-1/2 -translate-x-1/2 flex items-center gap-1 bg-white/[0.03] p-1 rounded-xl border border-white/5 backdrop-blur-md">
        <A href="/" end class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
          <div class="w-1 h-1 rounded-full bg-primary-500 opacity-0 [.active_&]:opacity-100 transition-opacity"></div>
          Terminal
        </A>
        <A href="/strategies" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
          <div class="w-1 h-1 rounded-full bg-primary-500 opacity-0 [.active_&]:opacity-100 transition-opacity"></div>
          Strategies
        </A>
        <A href="/signals" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
          <div class="w-1 h-1 rounded-full bg-primary-500 opacity-0 [.active_&]:opacity-100 transition-opacity"></div>
          Signals
        </A>
        <A href="/analysis" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
          <div class="w-1 h-1 rounded-full bg-primary-500 opacity-0 [.active_&]:opacity-100 transition-opacity"></div>
          Analysis
        </A>
        <A href="/settings" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkSettingsActive} inactiveClass="">
          <div class="w-1 h-1 rounded-full bg-cyan-400 opacity-0 [.active_&]:opacity-100 transition-opacity"></div>
          Settings
        </A>
      </nav>

      <div class="flex items-center gap-6 text-[10px]">
        <div
          class="flex items-center gap-2 group cursor-help"
          title={isIpVerified() ? `Verified: ${publicIpv4()}` : `Not Registered: ${publicIpv4()}`}
        >
          <div class={`w-2 h-2 rounded-full shadow-[0_0_8px] transition-colors ${isIpVerified() ? 'bg-emerald-400 shadow-emerald-400/40' : 'bg-rose-500 shadow-rose-500/40'}`}></div>
          <span class="text-gray-500 font-bold tracking-widest group-hover:text-gray-300 transition-colors">NET IDENTITY</span>
        </div>
        <div class="flex items-center gap-2 group cursor-help">
          <div class={`w-2 h-2 rounded-full shadow-[0_0_8px] transition-colors ${props.system?.ws_market_feed ? 'bg-emerald-400 shadow-emerald-400/40' : 'bg-gray-700'}`}></div>
          <span class="text-gray-500 font-bold tracking-widest group-hover:text-gray-300 transition-colors">MD FEED</span>
        </div>
        <div class="flex items-center gap-2 group cursor-help">
          <div class={`w-2 h-2 rounded-full shadow-[0_0_8px] transition-colors ${props.system?.scheduler === 'running' ? 'bg-emerald-400 shadow-emerald-400/40' : 'bg-rose-500 shadow-rose-500/40'}`}></div>
          <span class="text-gray-500 font-bold tracking-widest group-hover:text-gray-300 transition-colors">STG ENGINE</span>
        </div>
        <div class="flex items-center gap-2 group cursor-help">
          <div class={`w-2 h-2 rounded-full shadow-[0_0_8px] transition-colors ${props.system?.pnl_updater_running ? 'bg-emerald-400 shadow-emerald-400/40' : 'bg-gray-700'}`}></div>
          <span class="text-gray-500 font-bold tracking-widest group-hover:text-gray-300 transition-colors">PNL UPDATER</span>
        </div>
        <div class={`flex items-center gap-2 px-3 py-1.5 rounded-lg border transition-all duration-500 ${props.connected ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400' : 'bg-rose-500/10 border-rose-500/20 text-rose-400'}`}>
          <span class={`w-2 h-2 rounded-full ${props.connected ? 'bg-emerald-400 animate-pulse' : 'bg-rose-500'}`}></span>
          <span class="font-black tracking-[0.1em]">{props.connected ? 'CONNECTED' : 'DISCONNECTED'}</span>
        </div>
      </div>
    </header>
  )
}
