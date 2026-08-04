<script setup>
import { computed } from 'vue'

const props = defineProps({
  analysis:        [String, Object, null],
  snapshotData:    { default: null },
  snapshotLoading: { type: Boolean, default: false },
  snapshotError:   { default: null },
  onSnapshot:      { type: Function, default: null }
})

// Snapshot takes display priority over polled analysis
const displayText = computed(() => props.snapshotData ?? (
  typeof props.analysis === 'string' ? props.analysis :
  props.analysis ? JSON.stringify(props.analysis, null, 2) : null
))

const isLiveSnapshot = computed(() => props.snapshotData !== null)

function formatMarkdown(raw) {
  if (!raw) return ''
  return raw
    .replace(/\*\*(.*?)\*\*/g, '<strong class="text-white">$1</strong>')
    .replace(/#{1,3}\s(.*?)(\n|$)/g, '<div class="text-cyan-400 font-black text-xs tracking-wider mt-3 mb-1">$1</div>')
    .replace(/\n/g, '<br>')
}
</script>

<template>
  <div class="glass rounded-2xl p-6 glass-hover">
    <div class="flex items-center justify-between gap-3 mb-5">
      <div class="flex items-center gap-3">
        <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">🤖 AI Analysis</span>
        <span v-if="isLiveSnapshot"
          class="text-[9px] font-bold text-emerald-400 bg-emerald-400/10 px-2 py-0.5 rounded uppercase tracking-wider">
          🔴 Live snapshot
        </span>
        <span v-else-if="displayText" class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
      </div>

      <button
        v-if="onSnapshot"
        @click="onSnapshot()"
        :disabled="snapshotLoading"
        class="px-3 py-1.5 rounded-lg text-[9px] font-black uppercase tracking-widest glass border border-white/10 text-gray-400 hover:text-cyan-300 hover:border-cyan-500/30 transition-all duration-300 disabled:opacity-40 flex items-center gap-1.5"
      >
        <span v-if="snapshotLoading" class="w-3 h-3 border border-gray-400 border-t-transparent rounded-full animate-spin"></span>
        <span>{{ snapshotLoading ? 'Fetching...' : '🤖 Snapshot' }}</span>
      </button>
    </div>

    <!-- Inline error -->
    <div v-if="snapshotError" class="text-rose-400 text-[10px] font-bold mb-3 px-2 py-1 bg-rose-500/10 rounded">
      ⚠ {{ snapshotError }}
    </div>

    <!-- Analysis content (with loading overlay) -->
    <div class="relative">
      <div v-if="displayText"
        class="text-xs leading-relaxed text-gray-400 max-h-[500px] overflow-y-auto pr-2 scrollbar-thin"
        :class="{ 'opacity-30': snapshotLoading }"
        v-html="formatMarkdown(displayText)">
      </div>

      <div v-else-if="!snapshotLoading" class="text-center py-10">
        <div class="text-gray-600 text-[10px] font-bold tracking-widest uppercase">
          AI insights unavailable
        </div>
        <div class="text-gray-700 text-[9px] mt-2 tracking-wider">
          The AI model is either processing data or timed out. Please wait or check model performance.
        </div>
      </div>

      <!-- Loading overlay (when snapshotLoading and no existing content) -->
      <div v-if="snapshotLoading && !displayText" class="flex items-center justify-center py-10">
        <div class="w-5 h-5 border border-white/10 border-t-cyan-400 rounded-full animate-spin mr-3"></div>
        <span class="text-[10px] text-gray-500 font-bold tracking-widest uppercase">Generating snapshot...</span>
      </div>
    </div>
  </div>
</template>
