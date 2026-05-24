import { createMemo } from 'solid-js'
import { Show } from 'solid-js'
import { A } from '@solidjs/router'
import { useDashboardContext } from '../context/DashboardContext'
import { useFlash } from '../stores/useFlash'
import { confluenceLtfCompact, expiryBadgeMeta, subscribedRowByKey } from '../lib/expiryBadge'

function inr(val) {
  if (val == null) return '—'
  return Number(val).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

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

export default function Header(props) {
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

  const navLinkBase = 'px-5 py-1.5 rounded-lg text-[10px] font-black uppercase tracking-widest transition-all duration-300 hover:text-white flex items-center gap-2 group'
  const navLinkInactive = 'text-gray-500'
  const navLinkActive = 'bg-white/10 text-white shadow-[0_0_15px_rgba(255,255,255,0.05)] border border-white/10'
  const navLinkSettingsActive = 'bg-cyan-500/20 text-cyan-400 shadow-[0_0_15px_rgba(6,182,212,0.15)] border border-cyan-500/30'

  return (
    <div class="sticky top-0 z-50">
      <header class="glass border-b border-white/5 px-6 py-4 flex items-center justify-between">
        <div class="flex items-center gap-10">
          <div class="flex flex-col">
            <span class="text-[10px] font-black text-primary-400 tracking-[0.3em] uppercase">{props.mode} ENGINE</span>
            <span class="text-[8px] font-bold text-gray-500 tracking-widest mt-0.5 uppercase">Active Terminal</span>
          </div>

          <div class="hidden xl:flex items-center gap-8 border-l border-white/10 pl-10">
            <div class="flex flex-col gap-1">
              <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Nifty 50</span>
              <span class={`text-sm font-black text-white text-data transition-all duration-300 rounded px-1 ${niftyFlash()}`}>
                {inr(props.indices?.nifty)}
              </span>
              {(() => {
                const b = expiryBlock('NIFTY')
                return (
                  <div class="flex flex-col gap-0.5 items-start mt-0.5">
                    <span class={`text-[8px] font-black uppercase tracking-tighter px-1.5 py-0.5 rounded border ${b.className}`}>
                      {b.text}
                    </span>
                    <Show when={b.sub}>
                      <span class="text-[8px] font-bold text-gray-600">{b.sub}</span>
                    </Show>
                    <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'NIFTY'))}>
                      <span
                        class="text-[7px] font-mono text-gray-500 tracking-tight mt-0.5"
                        title="SMC Confluence LTF (Pine) — enable signals.enable_smc_confluence_digest"
                      >
                        {confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'NIFTY'))}
                      </span>
                    </Show>
                  </div>
                )
              })()}
            </div>
            <div class="flex flex-col gap-1">
              <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Bank Nifty</span>
              <span class={`text-sm font-black text-white text-data transition-all duration-300 rounded px-1 ${bankniftyFlash()}`}>
                {inr(props.indices?.banknifty)}
              </span>
              {(() => {
                const b = expiryBlock('BANKNIFTY')
                return (
                  <div class="flex flex-col gap-0.5 items-start mt-0.5">
                    <span class={`text-[8px] font-black uppercase tracking-tighter px-1.5 py-0.5 rounded border ${b.className}`}>
                      {b.text}
                    </span>
                    <Show when={b.sub}>
                      <span class="text-[8px] font-bold text-gray-600">{b.sub}</span>
                    </Show>
                    <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'BANKNIFTY'))}>
                      <span
                        class="text-[7px] font-mono text-gray-500 tracking-tight mt-0.5"
                        title="SMC Confluence LTF (Pine) — enable signals.enable_smc_confluence_digest"
                      >
                        {confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'BANKNIFTY'))}
                      </span>
                    </Show>
                  </div>
                )
              })()}
            </div>
            <div class="flex flex-col gap-1">
              <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Sensex</span>
              <span class={`text-sm font-black text-white text-data transition-all duration-300 rounded px-1 ${sensexFlash()}`}>
                {inr(props.indices?.sensex)}
              </span>
              {(() => {
                const b = expiryBlock('SENSEX')
                return (
                  <div class="flex flex-col gap-0.5 items-start mt-0.5">
                    <span class={`text-[8px] font-black uppercase tracking-tighter px-1.5 py-0.5 rounded border ${b.className}`}>
                      {b.text}
                    </span>
                    <Show when={b.sub}>
                      <span class="text-[8px] font-bold text-gray-600">{b.sub}</span>
                    </Show>
                    <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'SENSEX'))}>
                      <span
                        class="text-[7px] font-mono text-gray-500 tracking-tight mt-0.5"
                        title="SMC Confluence LTF (Pine) — enable signals.enable_smc_confluence_digest"
                      >
                        {confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'SENSEX'))}
                      </span>
                    </Show>
                  </div>
                )
              })()}
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
          <div class={`flex items-center gap-2 px-3 py-1.5 rounded-lg border transition-all duration-500 ${props.connected ? (props.isStale ? 'bg-amber-500/10 border-amber-500/20 text-amber-400' : 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400') : 'bg-rose-500/10 border-rose-500/20 text-rose-400'}`}>
            <span class={`w-2 h-2 rounded-full ${props.connected ? (props.isStale ? 'bg-amber-400 animate-pulse' : 'bg-emerald-400 animate-pulse') : 'bg-rose-500'}`}></span>
            <span class="font-black tracking-[0.1em]">
              {!props.connected ? 'DISCONNECTED' : (props.isStale ? 'STALE' : 'CONNECTED')}
            </span>
          </div>
        </div>
      </header>
      <MarketStatusBanner status={props.marketStatus} />
    </div>
  )
}

