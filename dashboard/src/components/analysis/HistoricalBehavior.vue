<script setup>
import { computed } from 'vue'

const props = defineProps({
  data: Object,
  loading: Boolean
})

const emit = defineEmits(['load'])

const ce = computed(() => props.data?.ce_aggregate)
const pe = computed(() => props.data?.pe_aggregate)
const cycles = computed(() => (props.data?.cycles || []).slice(-6))
const hasData = computed(() => props.data && !props.data.error)

function fmtPct(v) {
  if (v == null) return '—'
  return `${v >= 0 ? '+' : ''}${Number(v).toFixed(2)}%`
}

function pctClass(v) {
  if (v == null) return 'text-gray-500'
  return v >= 0 ? 'text-emerald-400' : 'text-rose-400'
}

function sessionBarColor(pct) {
  if (pct == null) return 'bg-gray-700'
  if (pct >= 1) return 'bg-emerald-500'
  if (pct <= -1) return 'bg-rose-500'
  return 'bg-amber-500'
}

function sessionOpacity(pct) {
  if (pct == null) return 0.3
  return Math.min(Math.abs(pct) / 5 + 0.4, 1)
}

const latestSessions = computed(() => {
  if (!props.data?.cycles?.length) return null
  const last = props.data.cycles[props.data.cycles.length - 1]
  return { ce: last.ce_sessions, pe: last.pe_sessions }
})
</script>

<template>
  <div class="glass rounded-2xl p-6 glass-hover">
    <div class="flex items-center justify-between mb-5">
      <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">📈 Historical Options Behavior</span>
      <span v-if="hasData" class="text-[9px] font-bold text-gray-600 tracking-wider">
        {{ data.weeks }} weeks · {{ ce?.n || 0 }} cycles
      </span>
    </div>

    <!-- Empty / Loading state -->
    <div v-if="!data && !loading" class="text-center py-12">
      <div class="text-gray-600 text-[10px] font-bold tracking-widest uppercase mb-3">No historical data loaded</div>
      <button
        @click="emit('load')"
        class="px-5 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest bg-primary-500/10 text-primary-400 border border-primary-500/20 hover:bg-primary-500/20 transition-all">
        📊 Load from DhanHQ
      </button>
      <div class="text-gray-700 text-[8px] mt-3 tracking-wider">First load may take 10–30 seconds</div>
    </div>

    <div v-else-if="loading" class="flex flex-col items-center py-12 gap-3">
      <div class="w-6 h-6 border-2 border-white/10 border-t-primary-500 rounded-full animate-spin"></div>
      <span class="text-[9px] font-bold text-gray-600 tracking-widest uppercase">Fetching DhanHQ data...</span>
    </div>

    <div v-else-if="data?.error" class="text-center py-8 text-rose-400 text-xs font-bold">{{ data.error }}</div>

    <!-- Data view -->
    <template v-else-if="hasData">
      <!-- Aggregate tables side by side -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <!-- CE Table -->
        <div v-if="ce">
          <div class="text-[9px] font-black text-cyan-400 tracking-widest uppercase mb-3">CE (Call) Aggregate</div>
          <table class="w-full text-[10px]">
            <thead>
              <tr class="border-b border-white/5">
                <th class="text-left py-2 font-black text-gray-600 tracking-widest uppercase">Metric</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Avg</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Best</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Worst</th>
              </tr>
            </thead>
            <tbody class="text-data">
              <tr class="border-b border-white/[0.03]" v-for="key in ['max_gain_pct', 'max_loss_pct', 'open_to_close_pct', 'post_peak_retrace', 'oi_change_pct', 'spot_change_pct']" :key="key">
                <td class="py-2 text-gray-500 text-[9px] font-bold tracking-wider">{{ key.replace(/_pct$/, '').replace(/_/g, ' ') }}</td>
                <td :class="['py-2 text-right font-bold', pctClass(ce.avg[key])]">{{ fmtPct(ce.avg[key]) }}</td>
                <td class="py-2 text-right text-gray-400">{{ fmtPct(ce.max[key]) }}</td>
                <td class="py-2 text-right text-gray-500">{{ fmtPct(ce.min[key]) }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- PE Table -->
        <div v-if="pe">
          <div class="text-[9px] font-black text-cyan-400 tracking-widest uppercase mb-3">PE (Put) Aggregate</div>
          <table class="w-full text-[10px]">
            <thead>
              <tr class="border-b border-white/5">
                <th class="text-left py-2 font-black text-gray-600 tracking-widest uppercase">Metric</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Avg</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Best</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Worst</th>
              </tr>
            </thead>
            <tbody class="text-data">
              <tr class="border-b border-white/[0.03]" v-for="key in ['max_gain_pct', 'max_loss_pct', 'open_to_close_pct', 'post_peak_retrace', 'oi_change_pct', 'spot_change_pct']" :key="key">
                <td class="py-2 text-gray-500 text-[9px] font-bold tracking-wider">{{ key.replace(/_pct$/, '').replace(/_/g, ' ') }}</td>
                <td :class="['py-2 text-right font-bold', pctClass(pe.avg[key])]">{{ fmtPct(pe.avg[key]) }}</td>
                <td class="py-2 text-right text-gray-400">{{ fmtPct(pe.max[key]) }}</td>
                <td class="py-2 text-right text-gray-500">{{ fmtPct(pe.min[key]) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Session Heatmaps -->
      <div v-if="latestSessions" class="mt-6 space-y-3">
        <div v-for="(label, side) in { ce: 'CE Sessions (Latest)', pe: 'PE Sessions (Latest)' }" :key="side"
          v-if="latestSessions[side]">
          <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-1.5">{{ label }}</div>
          <div class="flex gap-1 h-8 rounded-lg overflow-hidden">
            <div
              v-for="(sess, name) in latestSessions[side]" :key="name"
              v-if="sess"
              :class="['flex-1 flex items-center justify-center text-[8px] font-black text-white rounded transition-transform hover:scale-y-110', sessionBarColor(sess.oc_pct)]"
              :style="{ opacity: sessionOpacity(sess.oc_pct) }"
              :title="`${name}: ${fmtPct(sess.oc_pct)}`"
            >
              {{ name.substring(0, 4) }} {{ fmtPct(sess.oc_pct) }}
            </div>
          </div>
        </div>
      </div>

      <!-- Cycle Table -->
      <div v-if="cycles.length" class="mt-6">
        <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-2">Recent Expiry Cycles</div>
        <div class="overflow-x-auto">
          <table class="w-full text-[10px]">
            <thead>
              <tr class="border-b border-white/5">
                <th class="text-left py-2 font-black text-gray-600 tracking-widest uppercase">Expiry</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">CE Gain</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">CE Retr</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">PE Gain</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">PE Retr</th>
                <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Spot Δ</th>
              </tr>
            </thead>
            <tbody class="text-data">
              <tr v-for="c in cycles" :key="c.expiry" class="border-b border-white/[0.03] hover:bg-white/[0.02] transition-colors">
                <td class="py-2 text-gray-400">{{ c.expiry }}</td>
                <td :class="['py-2 text-right', pctClass(c.ce?.max_gain_pct)]">{{ fmtPct(c.ce?.max_gain_pct) }}</td>
                <td class="py-2 text-right text-amber-400">{{ fmtPct(c.ce?.post_peak_retrace) }}</td>
                <td :class="['py-2 text-right', pctClass(c.pe?.max_gain_pct)]">{{ fmtPct(c.pe?.max_gain_pct) }}</td>
                <td class="py-2 text-right text-amber-400">{{ fmtPct(c.pe?.post_peak_retrace) }}</td>
                <td :class="['py-2 text-right', pctClass(c.ce?.spot_change_pct)]">{{ fmtPct(c.ce?.spot_change_pct) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>
