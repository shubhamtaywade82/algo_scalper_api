import { createSignal, onMount, Show } from 'solid-js'
import { dashboardApiHeaders } from '../../lib/dashboardApi'

export default function FastEntryModePanel() {
  const [status, setStatus] = createSignal(null)
  const [loading, setLoading] = createSignal(true)
  const [saving, setSaving] = createSignal(false)
  const [error, setError] = createSignal('')

  async function fetchStatus() {
    setLoading(true)
    setError('')
    try {
      const response = await fetch('/api/settings/fast_entry_mode', { headers: dashboardApiHeaders() })
      const data = await response.json()
      if (!response.ok || !data.success) {
        throw new Error(data.error || 'Failed to load fast entry mode')
      }
      setStatus(data.fast_entry_mode)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function settingsToken() {
    let token = localStorage.getItem('algo_settings_token')
    if (token) return token

    token = window.prompt('Enter Settings Update Token (from your .env file):')
    if (token) {
      localStorage.setItem('algo_settings_token', token)
      return token
    }
    throw new Error('Settings update token required')
  }

  async function toggle(enabled) {
    setSaving(true)
    setError('')
    try {
      const token = await settingsToken()
      const response = await fetch('/api/settings/fast_entry_mode', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Settings-Update-Token': token
        },
        body: JSON.stringify({ enabled })
      })
      const data = await response.json()
      if (response.status === 401) {
        localStorage.removeItem('algo_settings_token')
        throw new Error('Invalid token. Try again.')
      }
      if (!response.ok || !data.success) {
        throw new Error(data.error || 'Update failed')
      }
      setStatus(data.fast_entry_mode)
    } catch (e) {
      setError(e.message)
    } finally {
      setSaving(false)
    }
  }

  onMount(() => { fetchStatus() })

  const effective = () => status()?.effective === true
  const persisted = () => status()?.persisted === true
  const envOverride = () => status()?.env_override === true

  return (
    <div class="bg-gray-900 border border-gray-800 rounded-lg shadow-lg shadow-black/50 p-6 mb-6">
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h2 class="text-lg font-bold text-gray-100 uppercase tracking-wide">Fast Entry Mode</h2>
          <p class="text-sm text-gray-500 mt-1 max-w-2xl">
            Off: strict intraday path (breakout arm + momentum gates). On: enter on 1m Supertrend only — exits and risk unchanged.
            Applies immediately; no daemon restart.
          </p>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <Show when={loading()}>
            <span class="text-xs text-gray-500 uppercase tracking-widest animate-pulse">Loading…</span>
          </Show>
          <Show when={!loading()}>
            <button
              type="button"
              disabled={saving() || envOverride()}
              onClick={() => toggle(!persisted())}
              class={`relative inline-flex h-9 w-16 items-center rounded-full border transition-colors ${
                effective()
                  ? 'bg-amber-900/60 border-amber-600'
                  : 'bg-gray-800 border-gray-600'
              } ${saving() || envOverride() ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
              aria-pressed={effective()}
            >
              <span
                class={`inline-block h-7 w-7 transform rounded-full bg-white shadow transition-transform ${
                  effective() ? 'translate-x-8' : 'translate-x-1'
                }`}
              />
            </button>
            <span class={`text-sm font-bold uppercase tracking-wider ${effective() ? 'text-amber-400' : 'text-gray-400'}`}>
              {effective() ? 'Fast' : 'Strict'}
            </span>
          </Show>
        </div>
      </div>

      <Show when={envOverride()}>
        <div class="mt-4 text-xs text-amber-300/90 border border-amber-800/50 bg-amber-950/30 rounded px-3 py-2">
          FAST_ENTRY_MODE env is set — it overrides the DB toggle until you unset it and restart the trading daemon.
        </div>
      </Show>

      <Show when={error()}>
        <div class="mt-4 text-xs text-red-400 border border-red-800/50 bg-red-950/30 rounded px-3 py-2">
          {error()}
        </div>
      </Show>
    </div>
  )
}
