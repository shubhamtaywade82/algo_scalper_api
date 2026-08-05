import { Show, createMemo } from 'solid-js'
import AnimatedNumber from './AnimatedNumber'

const CHIP_COLOR = {
  primary: 'bg-primary-500/10 text-primary-400',
  emerald: 'bg-emerald-500/10 text-emerald-400',
  amber: 'bg-amber-500/10 text-amber-400',
  violet: 'bg-violet-500/10 text-violet-400'
}

function IconChip(props) {
  return (
    <div class={`w-7 h-7 rounded-lg flex items-center justify-center shrink-0 ${CHIP_COLOR[props.color]}`}>
      <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        {props.children}
      </svg>
    </div>
  )
}

export default function StatsBar(props) {
  const stats = () => props.stats || {}
  const balance = () => props.balance || {}

  const netPnl = () => stats().total_pnl_rupees ?? 0
  const netPnlPct = () => stats().total_pnl_pct ?? 0
  const openPnl = () => stats().unrealized_pnl_rupees ?? 0
  const openPnlPct = () => stats().unrealized_pnl_pct ?? 0
  const realizedPnl = () => stats().realized_pnl_rupees ?? 0
  const realizedPnlPct = () => stats().realized_pnl_pct ?? 0

  const winRate = () => stats().win_rate ?? 0
  const winners = () => stats().winners ?? 0
  const totalTrades = () => stats().total_trades ?? 0

  const strategiesRunning = () => props.strategies?.running ?? 0
  const strategiesTotal = () => props.strategies?.total ?? 0

  const cash = () => balance().cash ?? 0
  const marginUsed = () => balance().margin_used ?? 0

  return (
    <div class="grid grid-cols-1 md:grid-cols-3 xl:grid-cols-7 gap-4">
      {/* 1. Net P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Net P&L (Today)</span>
          <IconChip color="primary">
            <path d="M3 17l6-6 4 4 8-8M15 7h6v6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
          </IconChip>
        </div>
        <div class="z-10">
          <div class="text-xl font-black text-data">
            <AnimatedNumber value={netPnl()} currency decimals={0} showSign pnlColor />
          </div>
          <span class="text-[10px] font-bold mt-1 block">
            <AnimatedNumber value={netPnlPct()} suffix="%" showSign pnlColor />
          </span>
        </div>

      </div>

      {/* 2. Open P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Open P&L</span>
          <IconChip color="amber">
            <rect width="20" height="14" x="2" y="7" rx="2" stroke-width="2"/>
            <path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" stroke-width="2" stroke-linecap="round"/>
          </IconChip>
        </div>
        <div class="z-10">
          <div class="text-xl font-black text-data">
            <AnimatedNumber value={openPnl()} currency decimals={0} showSign pnlColor />
          </div>
          <span class="text-[10px] font-bold mt-1 block">
            <AnimatedNumber value={openPnlPct()} suffix="%" showSign pnlColor />
          </span>
        </div>

      </div>

      {/* 3. Realized P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Realized P&L</span>
          <IconChip color="emerald">
            <path d="M8 21h8M12 17v4M7 4h10v4a5 5 0 0 1-10 0V4Z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M17 5h3a2 2 0 0 1-2 4M7 5H4a2 2 0 0 0 2 4" stroke-width="2" stroke-linecap="round"/>
          </IconChip>
        </div>
        <div>
          <div class="text-xl font-black text-data">
            <AnimatedNumber value={realizedPnl()} currency decimals={0} showSign pnlColor />
          </div>
          <span class="text-[10px] font-bold mt-1 block">
            <AnimatedNumber value={realizedPnlPct()} suffix="%" showSign pnlColor />
          </span>
        </div>
      </div>

      {/* 4. Win Rate */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Win Rate</span>
          <IconChip color="primary">
            <circle cx="12" cy="12" r="9" stroke-width="2"/>
            <circle cx="12" cy="12" r="5" stroke-width="2"/>
            <circle cx="12" cy="12" r="1" fill="currentColor" stroke-width="0"/>
          </IconChip>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            <AnimatedNumber value={winRate()} suffix="%" />
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            (<AnimatedNumber value={winners()} decimals={0} /> / <AnimatedNumber value={totalTrades()} decimals={0} />)
          </span>
        </div>
      </div>

      {/* 5. Total Trades */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Total Trades</span>
          <IconChip color="primary">
            <path d="M3 21V9M10 21V3M17 21v-7" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
          </IconChip>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            <AnimatedNumber value={totalTrades()} decimals={0} />
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            (Today)
          </span>
        </div>
      </div>

      {/* 6. Active Strategies */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Active Strategies</span>
          <IconChip color="violet">
            <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
          </IconChip>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            {strategiesRunning()} / {strategiesTotal()}
          </div>
          <Show when={strategiesRunning() > 0} fallback={
            <span class="text-[10px] font-bold text-gray-500 mt-1 flex items-center gap-1.5 uppercase tracking-wider">
              <span class="w-1.5 h-1.5 rounded-full bg-gray-500" /> Idle
            </span>
          }>
            <span class="text-[10px] font-bold text-emerald-400 mt-1 flex items-center gap-1.5 uppercase tracking-wider">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" /> Running
            </span>
          </Show>
        </div>
      </div>

      {/* 7. Available Balance */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Available Balance</span>
          <IconChip color="emerald">
            <rect width="18" height="14" x="3" y="5" rx="2" stroke-width="2"/>
            <path d="M3 10h18M7 15h4" stroke-width="2" stroke-linecap="round"/>
          </IconChip>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            <AnimatedNumber value={cash()} currency decimals={0} />
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            Margin: ₹<AnimatedNumber value={marginUsed()} decimals={0} />
          </span>
        </div>
      </div>
    </div>
  )
}
