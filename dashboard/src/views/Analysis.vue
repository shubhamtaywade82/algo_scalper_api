<script setup>
import { useAnalysis } from '../composables/useAnalysis'
import MarketOverview from '../components/analysis/MarketOverview.vue'
import SmcAnalysis from '../components/analysis/SmcAnalysis.vue'
import AiInsights from '../components/analysis/AiInsights.vue'
import HistoricalBehavior from '../components/analysis/HistoricalBehavior.vue'
import CalibrationPanel from '../components/analysis/CalibrationPanel.vue'

const {
  currentIndex, liveData, historicalData,
  loading, historicalLoading, error,
  fetchLive, fetchHistorical, switchIndex
} = useAnalysis()

const indices = ['NIFTY', 'SENSEX', 'BANKNIFTY']
</script>

<template>
  <div class="space-y-6">
    <!-- Index Tabs -->
    <div class="flex items-center justify-between flex-wrap gap-4">
      <div class="flex gap-1 p-1 rounded-xl glass border border-white/5">
        <button
          v-for="idx in indices" :key="idx"
          @click="switchIndex(idx)"
          :class="[
            'px-6 py-2 rounded-lg text-[10px] font-black uppercase tracking-[0.2em] transition-all duration-300',
            currentIndex === idx
              ? 'bg-primary-500 text-white shadow-[0_4px_15px_rgba(90,120,240,0.3)]'
              : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
          ]"
        >
          {{ idx }}
        </button>
      </div>

      <div class="flex gap-2">
        <button
          @click="fetchLive()"
          :disabled="loading"
          class="px-4 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest glass border border-white/10 text-gray-400 hover:text-white hover:border-primary-500/30 transition-all duration-300 disabled:opacity-40"
        >
          {{ loading ? '↻ Loading...' : '↻ Refresh' }}
        </button>
        <button
          @click="fetchHistorical()"
          :disabled="historicalLoading"
          class="px-4 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest glass border border-white/10 text-gray-400 hover:text-white hover:border-primary-500/30 transition-all duration-300 disabled:opacity-40"
        >
          {{ historicalLoading ? '📊 Fetching...' : '📊 Historical' }}
        </button>
      </div>
    </div>

    <!-- Loading state -->
    <div v-if="loading && !liveData" class="flex flex-col items-center justify-center py-20 gap-4">
      <div class="w-8 h-8 border-2 border-white/10 border-t-primary-500 rounded-full animate-spin"></div>
      <span class="text-[10px] font-black text-gray-500 tracking-widest uppercase">Analysing {{ currentIndex }}</span>
    </div>

    <!-- Error state -->
    <div v-else-if="error && !liveData" class="glass rounded-2xl p-8 text-center border border-rose-500/20">
      <div class="text-rose-400 text-sm font-bold">{{ error }}</div>
      <button @click="fetchLive()" class="mt-4 px-6 py-2 text-xs font-bold tracking-widest uppercase bg-white/5 rounded-lg border border-white/10 hover:border-primary-500/30 text-gray-400 hover:text-white transition-all">Retry</button>
    </div>

    <!-- Content -->
    <template v-else-if="liveData">
      <MarketOverview :data="liveData" />
      <SmcAnalysis :smc="liveData.smc" />
      <AiInsights :analysis="liveData.ai_analysis" />
      <HistoricalBehavior :data="historicalData" :loading="historicalLoading" @load="fetchHistorical" />
      <CalibrationPanel :data="historicalData" />
    </template>
  </div>
</template>
