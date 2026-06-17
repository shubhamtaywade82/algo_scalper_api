import { createSignal, onMount, For, Show } from 'solid-js'
import RecursiveFormNode from '../components/settings/RecursiveFormNode'
import CalibrationRunsPanel from '../components/settings/CalibrationRunsPanel'
import NetworkStatusPanel from '../components/settings/NetworkStatusPanel'
import FastEntryModePanel from '../components/settings/FastEntryModePanel'

export default function Settings() {
  const [configRoot, setConfigRoot] = createSignal(null)
  const [activeSection, setActiveSection] = createSignal('network_status')
  const [loading, setLoading] = createSignal(true)
  const [saving, setSaving] = createSignal(false)
  const [saveStatus, setSaveStatus] = createSignal(false)
  const [saveStatusMessage, setSaveStatusMessage] = createSignal('')
  const [saveStatusClass, setSaveStatusClass] = createSignal('')

  function showToast(message, type = 'success') {
    setSaveStatusMessage(message)
    setSaveStatusClass(type === 'success' ? 'text-cyan-400 border-cyan-800 bg-cyan-900/30' : 'text-red-400 border-red-800 bg-red-900/30')
    setSaveStatus(true)
    setTimeout(() => setSaveStatus(false), 4000)
  }

  async function fetchSettings() {
    setLoading(true)
    try {
      const response = await fetch('/api/settings')
      const data = await response.json()
      if (data.success) {
        setConfigRoot(data.config)
        if (activeSection() === 'network_status' || !configRoot()) {
          setActiveSection('network_status')
        }
      }
    } catch {
      showToast('Failed to load settings', 'error')
    } finally {
      setLoading(false)
    }
  }

  function handleUpdate(updatedNode) {
    const sec = activeSection()
    setConfigRoot(prev => ({ ...prev, [sec]: updatedNode }))
  }

  async function saveSettings() {
    let token = localStorage.getItem('algo_settings_token')
    if (!token) {
      token = window.prompt("Enter Settings Update Token (from your .env file):")
      if (token) {
        localStorage.setItem('algo_settings_token', token)
      } else {
        showToast('Canceled: Token required', 'error')
        return
      }
    }

    setSaving(true)
    try {
      const response = await fetch('/api/settings/bulk', {
        method: 'PATCH',
        headers: { 
          'Content-Type': 'application/json',
          'X-Settings-Update-Token': token
        },
        body: JSON.stringify({ settings: configRoot() })
      })
      const data = await response.json()
      if (response.status === 401) {
        localStorage.removeItem('algo_settings_token')
        throw new Error('Invalid token. Try again.')
      }
      if (data.success) {
        showToast('Settings saved successfully (Overrides stored in DB)')
      } else {
        throw new Error(data.error)
      }
    } catch (e) {
      showToast(e.message, 'error')
    } finally {
      setSaving(false)
    }
  }

  onMount(() => { fetchSettings() })

  return (
    <div class="settings-page w-full min-h-screen bg-gray-950 p-6 flex flex-col pt-24 font-mono text-gray-200">
      <div class="max-w-7xl mx-auto w-full">
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
            <Show when={saveStatus()}>
              <div class={`text-xs font-bold px-3 py-1.5 rounded bg-gray-900 border ${saveStatusClass()}`}>
                {saveStatusMessage()}
              </div>
            </Show>

            <button
              onClick={fetchSettings}
              disabled={loading()}
              class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 rounded border border-gray-700 transition-colors flex items-center gap-2 text-sm font-semibold"
            >
              RELOAD
            </button>

            <button
              onClick={saveSettings}
              disabled={saving()}
              class={`px-5 py-2 bg-cyan-900 hover:bg-cyan-800 text-cyan-100 rounded border border-cyan-700 transition-all flex items-center gap-2 text-sm font-bold shadow-[0_0_15px_rgba(8,145,178,0.2)] hover:shadow-[0_0_20px_rgba(8,145,178,0.4)] ${saving() ? 'opacity-50 cursor-not-allowed' : ''}`}
            >
              SAVE ALL CHANGES
            </button>
          </div>
        </div>

        <FastEntryModePanel />

        <Show when={loading() && !configRoot()}>
          <div class="flex justify-center py-20">
            <div class="text-cyan-500 font-bold uppercase tracking-widest animate-pulse">Loading Configuration Tree...</div>
          </div>
        </Show>

        <Show when={!loading() || configRoot()}>
          <div class="grid grid-cols-1 md:grid-cols-4 gap-6">
            <div class="md:col-span-1 sticky top-24 max-h-[calc(100vh-8rem)] overflow-y-auto pr-2">
              <div class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50">
                <div
                  onClick={() => setActiveSection('network_status')}
                  class={`px-4 py-3 text-xs font-black cursor-pointer border-l-2 transition-all uppercase tracking-widest ${
                    activeSection() === 'network_status'
                      ? 'bg-cyan-900/20 border-cyan-500 text-cyan-400'
                      : 'border-transparent text-gray-500 hover:bg-gray-800/50 hover:text-gray-200'
                  }`}
                >
                  NETWORK IDENTITY
                </div>
                <For each={configRoot() ? Object.keys(configRoot()) : []}>
                  {(key) => (
                    <div
                      onClick={() => setActiveSection(key)}
                      class={`px-4 py-3 text-sm font-semibold cursor-pointer border-l-2 transition-all capitalize ${
                        activeSection() === key
                          ? 'bg-gray-800 border-cyan-500 text-cyan-400'
                          : 'border-transparent text-gray-400 hover:bg-gray-800/50 hover:text-gray-200'
                      }`}
                    >
                      {String(key).replace(/_/g, ' ')}
                    </div>
                  )}
                </For>
              </div>
            </div>

            <div class="md:col-span-3">
              <Show when={activeSection() === 'network_status'}>
                <div class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50 p-6">
                  <h2 class="text-xl font-bold text-gray-100 uppercase tracking-wide border-b border-gray-800 pb-4 mb-6">Network Identity &amp; Static IP</h2>
                  <NetworkStatusPanel />
                </div>
              </Show>

              <Show when={activeSection() !== 'network_status' && configRoot() && configRoot()[activeSection()]}>
                <div class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg shadow-black/50 p-6">
                  <h2 class="text-xl font-bold text-gray-100 uppercase tracking-wide border-b border-gray-800 pb-4 mb-6">
                    {String(activeSection()).replace(/_/g, ' ')}
                  </h2>
                  <RecursiveFormNode
                    node={configRoot()[activeSection()]}
                    nodeKey={activeSection()}
                    onUpdate={handleUpdate}
                  />
                </div>
              </Show>
            </div>
          </div>
        </Show>
      </div>

      <div class="mt-12 max-w-7xl mx-auto w-full space-y-6">
        <For each={['NIFTY', 'SENSEX']}>
          {(sym) => <CalibrationRunsPanel symbol={sym} />}
        </For>
      </div>
    </div>
  )
}
