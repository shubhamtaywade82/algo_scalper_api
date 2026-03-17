<script setup>
import { ref, computed, onMounted } from 'vue'

const props = defineProps({
  symbol: { type: String, required: true }
})

const runs         = ref([])
const loading      = ref(false)
const error        = ref(null)
const applying     = ref(null)
const applyError   = ref(null)
const applySuccess = ref(false)

async function fetchRuns() {
  loading.value = true
  error.value   = null
  try {
    const res = await fetch('/api/calibration_runs?limit=20')
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const all = await res.json()
    runs.value = all.filter(r => r.symbol === props.symbol).slice(0, 5)
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function applyRun(run) {
  if (applying.value) return
  if (!window.confirm(`Apply calibration patch for ${props.symbol}? This will update live config.`)) return
  applying.value    = run.id
  applyError.value  = null
  applySuccess.value = false
  try {
    const res = await fetch(`/api/calibration_runs/${run.id}/apply`, { method: 'POST' })
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
    applySuccess.value = true
    setTimeout(() => { applySuccess.value = false }, 5000)
    await fetchRuns()
  } catch (e) {
    applyError.value = e.message
  } finally {
    applying.value = null
  }
}

function buildDiff(proposedPatch, currentSnapshot) {
  const pairs = []
  function walk(obj, prefix) {
    for (const [k, v] of Object.entries(obj || {})) {
      const fullKey = prefix ? `${prefix}.${k}` : k
      if (v !== null && typeof v === 'object') {
        walk(v, fullKey)
      } else {
        const cur = currentSnapshot?.[fullKey]
        pairs.push({ key: fullKey, current: cur ?? null, proposed: v })
      }
    }
  }
  walk(proposedPatch, '')
  return pairs
}

const pendingRuns = computed(() => runs.value.filter(r => !r.applied_at))

onMounted(fetchRuns)
</script>

<template>
  <div class="mt-8 border-t border-gray-800 pt-6">
    <div class="flex items-center justify-between mb-4">
      <h3 class="text-sm font-bold text-gray-300 uppercase tracking-widest">
        📊 Calibration Runs — {{ symbol }}
      </h3>
      <button
        @click="fetchRuns"
        :disabled="loading"
        class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider disabled:opacity-40"
      >
        {{ loading ? '↻ Loading...' : '↻ Refresh' }}
      </button>
    </div>

    <div v-if="error" class="text-rose-400 text-xs mb-4">⚠ {{ error }}</div>
    <div v-if="applyError" class="text-rose-400 text-xs mb-4">Apply failed: {{ applyError }}</div>
    <div v-if="applySuccess" class="text-emerald-400 text-xs mb-4 font-bold">
      ✅ Config updated — daemon picks up in ~30s
    </div>

    <div v-if="loading && !runs.length" class="text-gray-600 text-xs py-4">Loading...</div>

    <div v-else-if="!runs.length" class="text-gray-700 text-xs py-4">
      No calibration runs yet. Runs appear after the weekly job executes.
    </div>

    <div v-else class="space-y-3">
      <div
        v-for="run in runs"
        :key="run.id"
        class="bg-gray-900 border rounded-lg p-4 relative"
        :class="run.is_regime_shift ? 'border-amber-600/40' : 'border-gray-800'"
      >
        <!-- Regime shift badge -->
        <div v-if="run.is_regime_shift"
          class="absolute top-2 right-2 text-[9px] font-black text-amber-400 bg-amber-400/10 px-2 py-0.5 rounded uppercase tracking-wider">
          ⚠ Regime shift
        </div>

        <!-- Run header -->
        <div class="flex items-center gap-4 mb-3">
          <span class="text-[10px] font-bold text-gray-400">
            {{ new Date(run.created_at).toLocaleDateString('en-IN') }}
          </span>
          <span class="text-[10px] text-gray-600">{{ run.weeks_analyzed }}w · {{ run.strike_mode }}</span>
          <span v-if="run.applied_at" class="text-[9px] text-emerald-400 font-bold">
            ✓ Applied {{ new Date(run.applied_at).toLocaleDateString('en-IN') }}
            <span v-if="run.applied_by"> via {{ run.applied_by }}</span>
          </span>
        </div>

        <!-- Config diff table -->
        <div class="mb-3">
          <template v-for="diff in buildDiff(run.proposed_patch, run.current_snapshot)" :key="diff.key">
            <div class="flex items-center gap-2 text-[10px] font-mono py-0.5">
              <span class="text-gray-600 flex-1 truncate">{{ diff.key }}</span>
              <span class="text-gray-500">{{ diff.current !== null ? diff.current : '—' }}</span>
              <span class="text-gray-600 mx-1">→</span>
              <span class="text-cyan-400 font-bold">{{ diff.proposed }}</span>
            </div>
          </template>
          <div v-if="buildDiff(run.proposed_patch, run.current_snapshot).length === 0"
            class="text-gray-600 text-[9px] italic">
            No significant config changes (&lt;10% deviation from current)
          </div>
        </div>

        <!-- Apply button (only for pending runs) -->
        <button
          v-if="!run.applied_at"
          @click="applyRun(run)"
          :disabled="applying === run.id"
          class="px-4 py-1.5 text-[10px] font-black uppercase tracking-widest rounded border transition-all"
          :class="applying === run.id
            ? 'border-gray-700 text-gray-600 cursor-not-allowed'
            : 'border-cyan-700 text-cyan-400 hover:bg-cyan-900/20 hover:border-cyan-500'"
        >
          {{ applying === run.id ? 'Applying...' : 'Apply' }}
        </button>
      </div>
    </div>
  </div>
</template>
