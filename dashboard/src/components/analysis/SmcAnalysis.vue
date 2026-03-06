<script setup>
import { computed } from 'vue'

const props = defineProps({ smc: Object })

const decision = computed(() => props.smc?.decision)
const timeframes = computed(() => props.smc?.timeframes || {})

function decisionStyle(d) {
  const map = {
    call: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/25 shadow-[0_0_20px_rgba(16,185,129,0.15)]',
    put: 'bg-rose-500/15 text-rose-400 border-rose-500/25 shadow-[0_0_20px_rgba(239,68,68,0.15)]',
    no_trade: 'bg-amber-500/10 text-amber-400 border-amber-500/20'
  }
  return map[d] || 'bg-white/5 text-gray-400 border-white/10'
}

const tfLabels = { htf: 'HTF', mtf: 'MTF', ltf: 'LTF' }
const tfColors = { htf: 'border-l-cyan-400', mtf: 'border-l-blue-400', ltf: 'border-l-purple-400' }
</script>

<template>
  <div class="glass rounded-2xl p-6 glass-hover">
    <div class="flex items-center justify-between mb-5">
      <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">🏗️ SMC Analysis</span>
      <span v-if="decision" :class="['px-5 py-2 rounded-lg text-xs font-black tracking-[0.15em] uppercase border', decisionStyle(decision)]">
        {{ decision }}
      </span>
    </div>

    <div v-if="!smc" class="text-center py-8 text-gray-600 text-xs">No SMC data available</div>

    <div v-else class="space-y-2">
      <div
        v-for="(key, i) in ['htf', 'mtf', 'ltf']" :key="key"
        v-if="timeframes[key]"
        :class="['flex items-center gap-4 px-4 py-3 rounded-xl bg-white/[0.02] border-l-[3px] transition-all hover:bg-white/[0.04]', tfColors[key]]"
      >
        <span class="text-[10px] font-black tracking-widest text-cyan-400 min-w-[36px]">{{ tfLabels[key] }}</span>
        <span class="text-[9px] font-bold text-gray-500 min-w-[32px]">{{ timeframes[key].interval }}m</span>

        <div class="flex flex-wrap gap-1.5 flex-1" v-if="timeframes[key].context">
          <!-- Structure -->
          <span v-if="timeframes[key].context.structure?.trend"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-blue-500/10 text-blue-400 border border-blue-500/15">
            {{ timeframes[key].context.structure.trend }}
          </span>
          <span v-if="timeframes[key].context.structure?.choch"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-purple-500/10 text-purple-300 border border-purple-500/15">
            CHoCH
          </span>
          <span v-if="timeframes[key].context.structure?.bos"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-emerald-500/10 text-emerald-400 border border-emerald-500/15">
            BOS
          </span>

          <!-- Premium/Discount -->
          <span v-if="timeframes[key].context.premium_discount?.discount"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-emerald-500/10 text-emerald-400 border border-emerald-500/15">
            DISCOUNT
          </span>
          <span v-if="timeframes[key].context.premium_discount?.premium"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-rose-500/10 text-rose-400 border border-rose-500/15">
            PREMIUM
          </span>

          <!-- Liquidity -->
          <span v-if="timeframes[key].context.liquidity?.sell_side_taken"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-amber-500/10 text-amber-400 border border-amber-500/15">
            SSL Taken
          </span>
          <span v-if="timeframes[key].context.liquidity?.buy_side_taken"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-amber-500/10 text-amber-400 border border-amber-500/15">
            BSL Taken
          </span>
        </div>
      </div>

      <!-- AVRZ Row -->
      <div v-if="timeframes.ltf?.avrz"
        class="flex items-center gap-4 px-4 py-3 rounded-xl bg-white/[0.02] border-l-[3px] border-l-violet-400 hover:bg-white/[0.04] transition-all">
        <span class="text-[10px] font-black tracking-widest text-violet-400 min-w-[36px]">AVRZ</span>
        <div class="flex gap-1.5">
          <span :class="['px-2.5 py-1 rounded text-[9px] font-bold tracking-wider border',
            timeframes.ltf.avrz.rejection
              ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/15'
              : 'bg-amber-500/10 text-amber-400 border-amber-500/15']">
            {{ timeframes.ltf.avrz.rejection ? 'Rejection ✓' : 'No Rejection' }}
          </span>
          <span v-if="timeframes.ltf.avrz.zone"
            class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-blue-500/10 text-blue-400 border border-blue-500/15">
            {{ timeframes.ltf.avrz.zone }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
