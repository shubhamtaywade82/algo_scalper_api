<template>
  <div class="settings-page w-full min-h-screen bg-gray-950 p-6 flex flex-col pt-24 font-mono text-gray-200">
    <div class="max-w-7xl mx-auto w-full">
      <!-- Header -->
      <div class="flex justify-between items-center mb-8 border-b border-gray-800 pb-4">
        <div>
          <h1 class="text-2xl font-bold text-gray-100 flex items-center gap-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-cyan-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            ALGO SETTINGS (FULL)
          </h1>
          <p class="text-sm text-gray-500 mt-1">Configure ALL parameters mapped dynamically from algo.yml</p>
        </div>

        <div class="flex items-center gap-4">
          <div v-if="saveStatus" :class="['text-xs font-bold px-3 py-1.5 rounded bg-gray-900 border', saveStatusClass]">
            {{ saveStatusMessage }}
          </div>

          <button
            @click="fetchSettings"
            class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 rounded border border-gray-700 transition-colors flex items-center gap-2 text-sm font-semibold"
            :disabled="loading"
          >
            <!-- Reload icon -->
            RELOAD
          </button>

          <button
            @click="saveSettings"
            class="px-5 py-2 bg-cyan-900 hover:bg-cyan-800 text-cyan-100 rounded border border-cyan-700 transition-all flex items-center gap-2 text-sm font-bold shadow-[0_0_15px_rgba(8,145,178,0.2)] hover:shadow-[0_0_20px_rgba(8,145,178,0.4)]"
            :disabled="saving"
            :class="{'opacity-50 cursor-not-allowed': saving}"
          >
            <!-- Save icon -->
            SAVE ALL CHANGES
          </button>
        </div>
      </div>

      <div v-if="loading && !configRoot" class="flex justify-center py-20">
        <div class="text-cyan-500 font-bold uppercase tracking-widest animate-pulse">Loading Configuration Tree...</div>
      </div>

      <!-- JSON Tree Editor -->
      <div v-else class="grid grid-cols-1 md:grid-cols-4 gap-6">

        <!-- Sidebar Navigation (Top-level keys) -->
        <div class="md:col-span-1 sticky top-24 max-h-[calc(100vh-8rem)] overflow-y-auto pr-2 scrollbar-thin">
          <div class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50">
            <div
              @click="activeSection = 'network_status'"
              :class="[
                'px-4 py-3 text-xs font-black cursor-pointer border-l-2 transition-all uppercase tracking-widest',
                activeSection === 'network_status'
                  ? 'bg-cyan-900/20 border-cyan-500 text-cyan-400'
                  : 'border-transparent text-gray-500 hover:bg-gray-800/50 hover:text-gray-200'
              ]"
            >
              NETWORK IDENTITY
            </div>
            <div
              v-for="(value, key) in configRoot"
              :key="key"
              @click="activeSection = key"
              :class="[
                'px-4 py-3 text-sm font-semibold cursor-pointer border-l-2 transition-all capitalize',
                activeSection === key
                  ? 'bg-gray-800 border-cyan-500 text-cyan-400'
                  : 'border-transparent text-gray-400 hover:bg-gray-800/50 hover:text-gray-200'
              ]"
            >
              {{ String(key).replace(/_/g, ' ') }}
            </div>
          </div>
        </div>

        <!-- Main Content Area (Recursive JSON Form or Network Panel) -->
        <div class="md:col-span-3">
          <div
            v-if="activeSection === 'network_status'"
            class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50 p-6"
          >
            <h2 class="text-xl font-bold text-gray-100 uppercase tracking-wide border-b border-gray-800 pb-4 mb-6">Network Identity &amp; Static IP</h2>
            <NetworkStatusPanel />
          </div>

          <div
            v-else-if="activeSection && configRoot[activeSection]"
            class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50 p-6"
          >
            <h2 class="text-xl font-bold text-gray-100 uppercase tracking-wide border-b border-gray-800 pb-4 mb-6">{{ String(activeSection).replace(/_/g, ' ') }}</h2>

            <RecursiveFormNode
              :node="configRoot[activeSection]"
              :nodeKey="activeSection"
              @update="handleUpdate"
            />

          </div>
        </div>

      </div>
    </div>

    <!-- Calibration Runs Panels -->
    <div class="mt-12 max-w-7xl mx-auto w-full space-y-6">
      <CalibrationRunsPanel
        v-for="sym in ['NIFTY', 'SENSEX']"
        :key="sym"
        :symbol="sym"
      />
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import RecursiveFormNode from '../components/settings/RecursiveFormNode.vue'
import CalibrationRunsPanel from '../components/settings/CalibrationRunsPanel.vue'
import NetworkStatusPanel from '../components/settings/NetworkStatusPanel.vue'

const configRoot = ref(null)
const activeSection = ref('network_status')
const loading = ref(true)
const saving = ref(false)
const saveStatus = ref(false)
const saveStatusMessage = ref('')
const saveStatusClass = ref('')

const showToast = (message, type = 'success') => {
  saveStatusMessage.value = message
  saveStatusClass.value = type === 'success' ? 'text-cyan-400 border-cyan-800 bg-cyan-900/30' : 'text-red-400 border-red-800 bg-red-900/30'
  saveStatus.value = true
  setTimeout(() => saveStatus.value = false, 4000)
}

const fetchSettings = async () => {
  loading.value = true
  try {
    const response = await fetch('/api/settings')
    const data = await response.json()
    if (data.success) {
      configRoot.value = data.config
      if (!activeSection.value) {
        activeSection.value = Object.keys(data.config)[0]
      }
    }
  } catch (error) {
    showToast('Failed to load settings', 'error')
  } finally {
    loading.value = false
  }
}

// Emitted by children components when a deep value changes
const handleUpdate = (updatedNode) => {
  configRoot.value[activeSection.value] = updatedNode
}

const saveSettings = async () => {
  saving.value = true
  try {
    const response = await fetch('/api/settings/bulk', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ settings: configRoot.value })
    })
    const data = await response.json()
    if (data.success) {
      showToast('Settings saved successfully (Overrides stored in DB)')
    } else {
      throw new Error(data.error)
    }
  } catch (error) {
    showToast(error.message, 'error')
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  fetchSettings()
})
</script>
