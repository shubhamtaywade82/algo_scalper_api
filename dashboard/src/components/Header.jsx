import { createMemo } from 'solid-js'
import { A } from '@solidjs/router'
import { useDashboardContext } from '../context/DashboardContext'
import { useFlash } from '../stores/useFlash'

function inr(val) {
  if (val == null) return '—'
  return Number(val).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
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

  return (
    <div class="sticky top-0 z-50">
      <header class="glass border-b border-white/5 px-6 py-4 flex items-center justify-between gap-4">
        {/* Left Section: title & tickers */}
        <div class="flex items-center gap-6 min-w-0 flex-1">
          <div class="flex flex-col shrink-0">
            <span class="text-[10px] font-black text-primary-400 tracking-[0.3em] uppercase">{props.mode} ENGINE</span>
            <span class="text-[8px] font-bold text-gray-500 tracking-widest mt-0.5 uppercase">Active Terminal</span>
          </div>

          <div class="hidden xl:flex items-center gap-2.5 border-l border-white/10 pl-4 min-w-0">
            {/* Nifty 50 Card */}
            <a
              href="/charts?symbol=NIFTY"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 bg-white/[0.02] border border-white/5 rounded-2xl px-3 py-1.5 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[8px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Nifty 50</span>
                <span class={`text-xs font-black text-white text-data transition-all duration-300 rounded px-0.5 mt-0.5 ${niftyFlash()}`}>
                  <AnimatedNumber value={props.indices?.nifty} decimals={2} nullDisplay="—" />
                </span>
              </div>
              <div class="flex flex-col items-end gap-1">
                {(() => {
                  const b = expiryBlock('NIFTY')
                  return (
                    <>
                      <span class={`text-[7px] font-black uppercase tracking-tight px-1.5 py-0.5 rounded border leading-none ${b.className}`}>
                        {b.text}
                      </span>
                      <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'NIFTY'))}>
                        <span
                          class="text-[6px] font-mono text-gray-500 leading-none tracking-tighter"
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
              class="flex items-center gap-2 bg-white/[0.02] border border-white/5 rounded-2xl px-3 py-1.5 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[8px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Bank Nifty</span>
                <span class={`text-xs font-black text-white text-data transition-all duration-300 rounded px-0.5 mt-0.5 ${bankniftyFlash()}`}>
                  <AnimatedNumber value={props.indices?.banknifty} decimals={2} nullDisplay="—" />
                </span>
              </div>
              <div class="flex flex-col items-end gap-1">
                {(() => {
                  const b = expiryBlock('BANKNIFTY')
                  return (
                    <>
                      <span class={`text-[7px] font-black uppercase tracking-tight px-1.5 py-0.5 rounded border leading-none ${b.className}`}>
                        {b.text}
                      </span>
                      <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'BANKNIFTY'))}>
                        <span
                          class="text-[6px] font-mono text-gray-500 leading-none tracking-tighter"
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
              class="flex items-center gap-2 bg-white/[0.02] border border-white/5 rounded-2xl px-3 py-1.5 hover:bg-white/[0.04] hover:border-primary-500/20 hover:shadow-[0_0_15px_rgba(59,130,246,0.1)] transition-all duration-300 group cursor-pointer"
            >
              <div class="flex flex-col">
                <span class="text-[8px] font-black text-gray-500 tracking-wider uppercase group-hover:text-primary-400 transition-colors">Sensex</span>
                <span class={`text-xs font-black text-white text-data transition-all duration-300 rounded px-0.5 mt-0.5 ${sensexFlash()}`}>
                  <AnimatedNumber value={props.indices?.sensex} decimals={2} nullDisplay="—" />
                </span>
              </div>
              <div class="flex flex-col items-end gap-1">
                {(() => {
                  const b = expiryBlock('SENSEX')
                  return (
                    <>
                      <span class={`text-[7px] font-black uppercase tracking-tight px-1.5 py-0.5 rounded border leading-none ${b.className}`}>
                        {b.text}
                      </span>
                      <Show when={confluenceLtfCompact(subscribedRowByKey(props.subscribedIndices, 'SENSEX'))}>
                        <span
                          class="text-[6px] font-mono text-gray-500 leading-none tracking-tighter"
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

        {/* Center Section: Navigation */}
        <nav class="flex items-center gap-1 bg-white/[0.02] p-1 rounded-2xl border border-white/5 backdrop-blur-xl shrink-0">
          <A href="/" end class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <rect width="20" height="16" x="2" y="4" rx="2" stroke-width="2.5"/>
              <path d="m7 10 2 2-2 2m5-2h5" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            Terminal
          </A>
          <A href="/strategies" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            Strategies
          </A>
          <A href="/alpha" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="m12 3-1.912 5.886H3.886L9.088 12.5l-1.912 5.886L12 14.772l4.824 3.614-1.912-5.886 5.202-3.614h-6.202L12 3z" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            Alpha
          </A>
          <A href="/signals" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            Signals
          </A>
          <A href="/analysis" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="M3 3v18h18M18.7 8l-5.1 5.2-2.8-2.7L7 14.3" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            Analysis
          </A>
          <A href="/ledger" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkLedgerActive} inactiveClass="">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
              <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
              <path d="M8 7h8M8 11h8M8 15h4" stroke-width="2.5" stroke-linecap="round"/>
            </svg>
            Ledger
          </A>
          <A href="/settings" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkSettingsActive} inactiveClass="">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.1a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
              <circle cx="12" cy="12" r="3" stroke-width="2.5"/>
            </svg>
            Settings
          </A>
        </nav>

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
