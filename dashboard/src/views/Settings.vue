<template>
  <div class="settings-page w-full min-h-screen bg-gray-950 p-6 flex flex-col pt-24 font-mono text-gray-200">
    <div class="max-w-5xl mx-auto w-full">
      <!-- Header -->
      <div class="flex justify-between items-center mb-8 border-b border-gray-800 pb-4">
        <div>
          <h1 class="text-2xl font-bold text-gray-100 flex items-center gap-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-cyan-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            ALGO SETTINGS
          </h1>
          <p class="text-sm text-gray-500 mt-1">Configure trading engine parameters dynamically.</p>
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
            <svg v-if="loading" class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            RELOAD
          </button>

          <button
            @click="saveSettings"
            class="px-5 py-2 bg-cyan-900 hover:bg-cyan-800 text-cyan-100 rounded border border-cyan-700 transition-all flex items-center gap-2 text-sm font-bold shadow-[0_0_15px_rgba(8,145,178,0.2)] hover:shadow-[0_0_20px_rgba(8,145,178,0.4)]"
            :disabled="saving || !hasChanges"
            :class="{'opacity-50 cursor-not-allowed': !hasChanges && !saving}"
          >
            <svg v-if="saving" class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <svg v-else xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4" />
            </svg>
            SAVE CHANGES
          </button>
        </div>
      </div>

      <!-- Loading State -->
      <div v-if="loading && Object.keys(groupedSettings).length === 0" class="flex justify-center items-center py-20">
        <div class="animate-pulse flex flex-col items-center gap-4">
          <div class="h-8 w-8 rounded-full border-t-2 border-r-2 border-cyan-500 animate-spin"></div>
          <p class="text-xs text-cyan-500 font-bold uppercase tracking-widest">Loading Settings Configuration...</p>
        </div>
      </div>

      <!-- Settings Layout -->
      <div v-else class="grid grid-cols-1 md:grid-cols-12 gap-6 items-start">

        <!-- Sidebar Navigation -->
        <div class="md:col-span-3 sticky top-24">
          <div class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50">
            <div
              v-for="(settings, category) in groupedSettings"
              :key="category"
              @click="activeCategory = category"
              :class="[
                'px-4 py-3 text-sm font-semibold cursor-pointer border-l-2 transition-all',
                activeCategory === category
                  ? 'bg-gray-800 border-cyan-500 text-cyan-400'
                  : 'border-transparent text-gray-400 hover:bg-gray-800/50 hover:text-gray-200'
              ]"
            >
              {{ category }}
            </div>
          </div>
        </div>

        <!-- Main Content Area -->
        <div class="md:col-span-9 space-y-6">
          <div
            v-for="(settings, category) in groupedSettings"
            :key="`content-${category}`"
            v-show="activeCategory === category"
            class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50"
          >
            <div class="bg-gray-800/80 px-5 py-3 border-b border-gray-700/50">
              <h2 class="text-lg font-bold text-gray-200 uppercase tracking-wide">{{ category }}</h2>
            </div>

            <div class="divide-y divide-gray-800/60 p-5 space-y-5">

              <div v-for="setting in settings" :key="setting.key" class="pt-5 first:pt-0 flex flex-col md:flex-row md:items-start justify-between gap-6">
                <!-- Info Column -->
                <div class="flex-1">
                  <span class="text-sm font-bold text-gray-300 block mb-1">
                    {{ formatSettingName(setting.key) }}
                    <span
                      v-if="hasChanged(setting)"
                      class="inline-block ml-2 w-2 h-2 rounded-full bg-amber-500 animate-pulse"
                      title="Unsaved changes"
                    ></span>
                  </span>
                  <p class="text-xs text-gray-500 leading-relaxed">{{ setting.description }}</p>
                  <code class="text-[10px] text-gray-600 font-mono mt-2 block">Key: {{ setting.key }}</code>
                </div>

                <!-- Input Column -->
                <div class="w-full md:w-64 shrink-0 flex items-center justify-end">

                  <!-- Boolean Toggle -->
                  <div v-if="setting.type === 'boolean'" class="relative inline-block w-12 mr-2 align-middle select-none">
                    <input
                      type="checkbox"
                      :id="setting.key"
                      v-model="pendingChanges[setting.key]"
                      class="toggle-checkbox absolute block w-6 h-6 rounded-full bg-white border-4 appearance-none cursor-pointer transition-transform duration-200 ease-in-out"
                      :class="pendingChanges[setting.key] ? 'translate-x-6 border-cyan-500' : 'translate-x-0 border-gray-600'"
                    />
                    <label
                      :for="setting.key"
                      class="toggle-label block overflow-hidden h-6 rounded-full bg-gray-600 cursor-pointer transition-colors duration-200 ease-in-out"
                      :class="pendingChanges[setting.key] ? 'bg-cyan-600' : 'bg-gray-800 border box-content border-gray-600'"
                    ></label>
                  </div>

                  <!-- Integer / Number Input -->
                  <div v-else-if="setting.type === 'integer' || setting.type === 'float'" class="relative w-full">
                    <input
                      type="number"
                      :step="setting.type === 'float' ? '0.01' : '1'"
                      v-model="pendingChanges[setting.key]"
                      class="w-full bg-gray-950 border border-gray-700 text-gray-200 text-sm rounded focus:ring-1 focus:ring-cyan-500 focus:border-cyan-500 outline-none block p-2.5 shadow-inner"
                    />
                  </div>

                  <!-- String Input -->
                  <div v-else-if="setting.type === 'string'" class="relative w-full">
                    <input
                      type="text"
                      v-model="pendingChanges[setting.key]"
                      class="w-full bg-gray-950 border border-gray-700 text-gray-200 text-sm rounded focus:ring-1 focus:ring-cyan-500 focus:border-cyan-500 outline-none block p-2.5 shadow-inner font-mono"
                    />
                  </div>

                </div>
              </div>

            </div>
          </div>
        </div>

      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, reactive } from 'vue'

const groupedSettings = ref({})
const activeCategory = ref('')
const loading = ref(true)
const saving = ref(false)

const saveStatus = ref(false)
const saveStatusMessage = ref('')
const saveStatusClass = ref('')

// Store the original state fetched from API
const originalState = reactive({})
// Store the pending visual changes made by user
const pendingChanges = reactive({})

const hasChanges = computed(() => {
  return Object.keys(pendingChanges).some(key => {
    return pendingChanges[key] !== originalState[key]
  })
})

const formatSettingName = (key) => {
  return key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())
}

const hasChanged = (setting) => {
  return pendingChanges[setting.key] !== originalState[setting.key]
}

const showToast = (message, type = 'success') => {
  saveStatusMessage.value = message
  saveStatusClass.value = type === 'success'
    ? 'text-cyan-400 border-cyan-800 bg-cyan-900/30'
    : 'text-red-400 border-red-800 bg-red-900/30'
  saveStatus.value = true

  setTimeout(() => {
    saveStatus.value = false
  }, 4000)
}

const fetchSettings = async () => {
  loading.value = true
  try {
    const response = await fetch('/api/settings')
    const data = await response.json()

    if (data.success) {
      groupedSettings.value = data.grouped

      // Set the first category active by default if none selected
      if (!activeCategory.value) {
        activeCategory.value = Object.keys(data.grouped)[0]
      }

      // Initialize reactive states
      data.settings.forEach(setting => {
        let val = setting.value

        // Ensure proper typing for inputs
        if (setting.type === 'integer') val = parseInt(val)
        if (setting.type === 'float') val = parseFloat(val)

        originalState[setting.key] = val
        pendingChanges[setting.key] = val
      })
    }
  } catch (error) {
    console.error('Failed to load settings:', error)
    showToast('Failed to load settings', 'error')
  } finally {
    loading.value = false
  }
}

const saveSettings = async () => {
  if (!hasChanges.value) return

  saving.value = true

  // Extract only the fields that were actually changed
  const payload = Object.keys(pendingChanges)
    .filter(key => pendingChanges[key] !== originalState[key])
    .map(key => ({ key: key, value: pendingChanges[key] }))

  try {
    const response = await fetch('/api/settings/bulk', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ settings: payload })
    })

    const data = await response.json()

    if (data.success) {
      // Sync original state with the new changes locally
      payload.forEach(item => {
        originalState[item.key] = item.value
      })
      showToast('Settings successfully updated', 'success')
    } else {
      throw new Error(data.error || 'Failed to save settings')
    }
  } catch (error) {
    console.error('Failed to save settings:', error)
    showToast(error.message, 'error')
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  fetchSettings()
})
</script>

<style scoped>
/* Custom toggle switch CSS (Tailwind doesn't have a native one) */
.toggle-checkbox:checked {
  right: 0;
  border-color: #06b6d4; /* cyan-500 */
}
.toggle-checkbox:checked + .toggle-label {
  background-color: #0891b2; /* cyan-600 */
}
</style>
