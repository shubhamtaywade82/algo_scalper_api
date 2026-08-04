<script setup>
import { computed } from 'vue'

const props = defineProps({ analysis: [String, Object, null] })

const text = computed(() => {
  if (!props.analysis) return null
  if (typeof props.analysis === 'string') return props.analysis
  return JSON.stringify(props.analysis, null, 2)
})

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
    <div class="flex items-center gap-3 mb-5">
      <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">🤖 AI Analysis</span>
      <span v-if="text" class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
    </div>

    <div v-if="text"
      class="text-xs leading-relaxed text-gray-400 max-h-[500px] overflow-y-auto pr-2 scrollbar-thin"
      v-html="formatMarkdown(text)">
    </div>

    <div v-else class="text-center py-10">
      <div class="text-gray-600 text-[10px] font-bold tracking-widest uppercase">
        AI insights unavailable
      </div>
      <div class="text-gray-700 text-[9px] mt-2 tracking-wider">
        The AI model is either processing data or timed out. Please wait or check model performance.
      </div>
    </div>
  </div>
</template>
