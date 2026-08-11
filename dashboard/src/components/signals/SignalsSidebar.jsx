import { createSignal, onMount, For, Show } from 'solid-js'
import { dashboardApiHeaders } from '../../lib/dashboardApi'

const TOGGLE_GROUPS = [
  {
    title: 'Market & Signal Engine',
    colorClass: 'bg-amber-500 shadow-[0_0_8px_rgba(245,158,11,0.8)]',
    toggles: [
      {
        id: 'enable_trading_context_gate',
        label: 'Trading Context Gate',
        desc: 'Filter entries based on broader market trend context.',
        path: ['signals', 'enable_trading_context_gate']
      },
      {
        id: 'block_choppy_regime',
        label: 'Block Choppy Regime',
        desc: 'Block entries when market classification is CHOPPY.',
        path: ['entry_quality', 'gates', 'block_choppy_regime']
      },
      {
        id: 'market_context_gate',
        label: 'Market Context (HTF)',
        desc: 'Block if 1m signal completely opposes HTF trend structure.',
        path: ['market_context', 'gate', 'enabled']
      },
      {
        id: 'smc_confluence',
        label: 'SMC Confluence Gating',
        desc: 'Block entries without Institutional Smart Money confirmation.',
        path: ['signals', 'enable_smc_confluence_gating']
      },
      {
        id: 'smc_navigator_overlay',
        label: 'SMC Navigator Overlay',
        desc: 'Block entries into unmitigated institutional Order Blocks/FVGs.',
        path: ['signals', 'enable_smc_navigator_overlay']
      }
    ]
  },
  {
    title: 'Options & Premium',
    colorClass: 'bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.8)]',
    toggles: [
      {
        id: 'options_iv_theta_gate',
        label: 'IV Rank & Theta Risk',
        desc: 'Block overly expensive (IV spike) or heavily decaying premiums.',
        path: ['signals', 'options_analysis_gate', 'enabled']
      },
      {
        id: 'enable_option_premium_momentum_gate',
        label: 'Premium Momentum',
        desc: 'Require option price to have advanced favorably prior to entry.',
        path: ['signals', 'enable_option_premium_momentum_gate']
      },
      {
        id: 'enable_strike_score_floor_gate',
        label: 'Strike Score Floor',
        desc: 'Ensure strike passes the minimum proprietary institutional score.',
        path: ['signals', 'enable_strike_score_floor_gate']
      },
      {
        id: 'enable_expected_move_strike_gate',
        label: 'Expected Move Constraint',
        desc: 'Hard check for option premium vs short-term expected move.',
        path: ['signals', 'enable_expected_move_strike_gate']
      }
    ]
  },
  {
    title: 'Execution & Risk Guards',
    colorClass: 'bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.8)]',
    toggles: [
      {
        id: 'enable_time_regime_rules',
        label: 'Time Regime Rules',
        desc: 'Adapt or block entries based on current market time session.',
        path: ['risk', 'time_regimes', 'enabled']
      },
      {
        id: 'midday_guard',
        label: 'Midday Quality Guard',
        desc: 'Stricter quality hurdles required during the 11:30–13:30 chop zone.',
        path: ['midday_guard', 'enabled']
      },
      {
        id: 'loss_streak_guard',
        label: 'Loss Streak Guard',
        desc: 'Block new entries temporarily if a sequential loss limit is hit.',
        path: ['loss_streak_guard', 'enabled']
      },
      {
        id: 'daily_limits',
        label: 'Daily Max Loss Cap',
        desc: 'Halt all trading immediately if daily max loss % limit is breached.',
        path: ['risk', 'daily_limits', 'enable']
      }
    ]
  }
]

export default function SignalsSidebar() {
  const [config, setConfig] = createSignal({})
  const [loading, setLoading] = createSignal(true)
  const [updating, setUpdating] = createSignal(false)
  const [toastMessage, setToastMessage] = createSignal('')
  const [toastClass, setToastClass] = createSignal('')
  const [showToast, setShowToast] = createSignal(false)

  function displayToast(msg, type = 'success') {
    setToastMessage(msg)
    setToastClass(type === 'success' ? 'text-cyan-400 bg-cyan-900/30' : 'text-rose-400 bg-rose-900/30')
    setShowToast(true)
    setTimeout(() => setShowToast(false), 3000)
  }

  async function fetchSettings() {
    setLoading(true)
    try {
      const res = await fetch('/api/settings', { headers: dashboardApiHeaders() })
      const data = await res.json()
      if (data.success) {
        setConfig(data.config)
      }
    } catch (e) {
      console.error('Failed to load settings', e)
    } finally {
      setLoading(false)
    }
  }

  onMount(() => {
    fetchSettings()
  })

  function getValueByPath(obj, pathArr) {
    return pathArr.reduce((acc, current) => (acc && acc[current] !== undefined) ? acc[current] : undefined, obj)
  }

  async function toggleSetting(pathArr, currentValue) {
    if (updating()) return
    setUpdating(true)
    
    const newValue = !currentValue

    // Build the patch object recursively from path array
    const patch = {}
    let currentLevel = patch
    for (let i = 0; i < pathArr.length - 1; i++) {
      currentLevel[pathArr[i]] = {}
      currentLevel = currentLevel[pathArr[i]]
    }
    currentLevel[pathArr[pathArr.length - 1]] = newValue

    // Handle authentication token
    let token = localStorage.getItem('algo_settings_token')
    if (!token) {
      token = window.prompt("Enter Settings Update Token (from your .env file):")
      if (token) {
        localStorage.setItem('algo_settings_token', token)
      } else {
        setUpdating(false)
        displayToast('Canceled: Token required', 'error')
        return
      }
    }

    try {
      const resp = await fetch('/api/settings/deep_merge', {
        method: 'PATCH',
        headers: { 
          'Content-Type': 'application/json',
          'X-Settings-Update-Token': token
        },
        body: JSON.stringify({ patch })
      })
      const data = await resp.json()
      if (resp.status === 401) {
        localStorage.removeItem('algo_settings_token')
        throw new Error('Invalid token. Try again.')
      }
      if (data.success) {
        // Optimistically update local config
        const newConfig = JSON.parse(JSON.stringify(config()))
        let ref = newConfig
        for (let i = 0; i < pathArr.length - 1; i++) {
          if (!ref[pathArr[i]]) ref[pathArr[i]] = {}
          ref = ref[pathArr[i]]
        }
        ref[pathArr[pathArr.length - 1]] = newValue
        setConfig(newConfig)

        displayToast(`${pathArr[pathArr.length - 1]} updated to ${newValue}`)
      } else {
        throw new Error(data.error || 'Failed to update setting')
      }
    } catch (e) {
      displayToast(e.message, 'error')
    } finally {
      setUpdating(false)
    }
  }

  return (
    <div class="glass rounded-2xl border border-white/5 p-5 shadow-2xl flex flex-col gap-5 sticky top-24">
      
      <div class="flex items-center justify-between border-b border-white/5 pb-3">
        <h3 class="text-sm font-black text-white uppercase tracking-widest flex items-center gap-2">
          <span class="w-2 h-2 rounded-full bg-cyan-500 shadow-[0_0_8px_rgba(6,182,212,0.8)]"></span>
          Live Controls
        </h3>
        <Show when={showToast()}>
          <div class={`text-[9px] font-bold px-2 py-1 rounded truncate max-w-[120px] ${toastClass()}`}>
            {toastMessage()}
          </div>
        </Show>
      </div>

      <Show when={loading()}>
        <div class="py-10 text-center">
          <span class="text-cyan-500 font-bold text-xs uppercase tracking-widest animate-pulse">Loading Config...</span>
        </div>
      </Show>

      <Show when={!loading()}>
        <div class="flex flex-col gap-6">
          <For each={TOGGLE_GROUPS}>
            {(group) => (
              <div class="flex flex-col gap-3">
                <div class="flex items-center gap-2 px-1">
                  <span class={`w-1.5 h-1.5 rounded-full ${group.colorClass}`}></span>
                  <h4 class="text-[10px] font-black text-gray-400 uppercase tracking-widest">{group.title}</h4>
                </div>
                <div class="flex flex-col gap-2">
                  <For each={group.toggles}>
                    {(toggleDef) => {
                      const switchOn = () => getValueByPath(config(), toggleDef.path) === true

                      return (
                        <div class="flex flex-col gap-1.5 p-3 rounded-lg bg-white/[0.02] border border-white/[0.05] hover:bg-white/[0.04] transition-colors">
                          <div class="flex justify-between items-center">
                            <span class="text-[11px] font-bold text-gray-200 capitalize w-3/4 leading-tight">{toggleDef.label}</span>
                            <button
                              onClick={() => toggleSetting(toggleDef.path, switchOn())}
                              disabled={updating()}
                              class={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${updating() ? 'opacity-50' : 'opacity-100'} ${switchOn() ? 'bg-cyan-500 shadow-[0_0_10px_rgba(6,182,212,0.4)]' : 'bg-gray-700'}`}
                            >
                              <span class={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${switchOn() ? 'translate-x-4' : 'translate-x-0'}`} />
                            </button>
                          </div>
                          <span class="text-[9px] text-gray-500 leading-tight pr-4">{toggleDef.desc}</span>
                        </div>
                      )
                    }}
                  </For>
                </div>
              </div>
            )}
          </For>
        </div>
      </Show>

      <div class="mt-2 text-[9px] text-gray-600 italic tracking-wide text-center">
        Changes apply instantly to the daemon pipeline. No restart required.
      </div>

    </div>
  )
}
