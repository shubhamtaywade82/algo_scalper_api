import { createSignal, createMemo } from 'solid-js'
import { Show } from 'solid-js'
import { useDashboardContext } from '../../context/DashboardContext'

function daysRemaining(dateStr) {
  if (!dateStr) return null
  const target = new Date(dateStr)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  target.setHours(0, 0, 0, 0)
  const diffDays = Math.ceil((target - today) / (1000 * 60 * 60 * 24))
  return diffDays > 0 ? diffDays : 0
}

export default function NetworkStatusPanel() {
  const { publicIpv4, publicIpv6, registeredIps, config } = useDashboardContext()
  const [updating, setUpdating] = createSignal(false)

  const isIpVerified = createMemo(() => {
    const ips = registeredIps()
    if (!ips) return false
    const registered = [ips.primary_ip, ips.secondary_ip].filter(Boolean)
    return registered.includes(publicIpv4()) || (publicIpv6() !== 'None' && registered.includes(publicIpv6()))
  })

  const autoUpdateEnabled = createMemo(() => config()?.risk?.auto_update_ip === true)

  const canUpdateAny = createMemo(() => {
    const ips = registeredIps()
    if (!ips) return false
    const pDays = daysRemaining(ips.modification_allowed_date_for_primary_ip)
    const sDays = daysRemaining(ips.modification_allowed_date_for_secondary_ip)
    return (pDays === 0) || (sDays === 0)
  })

  async function triggerIpUpdate() {
    if (!confirm(`This will attempt to whitelist your current IPv4 (${publicIpv4()}) on Dhan. Continue?`)) return
    setUpdating(true)
    try {
      const res = await fetch('/api/settings/update_ip', { method: 'POST', headers: { 'Content-Type': 'application/json' } })
      const data = await res.json()
      if (data.success) {
        alert(`Success! Updated ${data.flag} slot to ${publicIpv4()}`)
        location.reload()
      } else {
        alert('Update failed: ' + data.error)
      }
    } catch {
      alert('Failed to connect to server')
    } finally {
      setUpdating(false)
    }
  }

  return (
    <div class="space-y-6">
      <div class={`p-4 rounded-lg border flex items-center justify-between ${isIpVerified() ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400' : 'bg-amber-500/10 border-amber-500/20 text-amber-400'}`}>
        <div class="flex items-center gap-3">
          <div class={`w-10 h-10 rounded-full flex items-center justify-center ${isIpVerified() ? 'bg-emerald-500/20' : 'bg-amber-500/20'}`}>
            <Show when={isIpVerified()} fallback={
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
            }>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
            </Show>
          </div>
          <div>
            <h3 class="font-bold uppercase tracking-wider">{isIpVerified() ? 'Verified Static IP' : 'Unregistered Identity'}</h3>
            <p class="text-xs opacity-70">{isIpVerified() ? 'Your current network identity matches Dhan whitelisted slots.' : 'Current IP is not registered on Dhan. Automated orders will fail.'}</p>
          </div>
        </div>
        <div class="text-right">
          <span class="text-[10px] font-black uppercase tracking-widest opacity-50 block mb-1">Dhan Compliance</span>
          <div class="flex flex-col items-end gap-2">
            <div class={`px-3 py-1 rounded-full text-[10px] font-black uppercase border ${isIpVerified() ? 'border-emerald-500/30' : 'border-amber-500/30'}`}>
              {isIpVerified() ? 'GATE OPEN' : 'GATE CLOSED'}
            </div>
            <Show when={!isIpVerified() && canUpdateAny()}>
              <button
                onClick={triggerIpUpdate}
                disabled={updating()}
                class="px-3 py-1.5 bg-cyan-600 hover:bg-cyan-500 text-white rounded text-[10px] font-black uppercase tracking-widest transition-all shadow-lg shadow-cyan-900/20 disabled:opacity-50"
              >
                {updating() ? 'UPDATING...' : 'WHITELIST CURRENT IP'}
              </button>
            </Show>
            <Show when={!isIpVerified() && !canUpdateAny()}>
              <div class="text-[9px] font-black text-amber-600 uppercase italic">Cooldown Active</div>
            </Show>
          </div>
        </div>
      </div>

      <div class="bg-gray-800/30 border border-gray-700/50 rounded-lg p-4 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <div class={`w-2 h-2 rounded-full ${autoUpdateEnabled() ? 'bg-emerald-500 animate-pulse' : 'bg-gray-600'}`}></div>
          <div>
            <span class="text-xs font-bold text-gray-300 uppercase tracking-widest">Auto-Sync Engine</span>
            <p class="text-[10px] text-gray-500">Automatically updates Dhan whitelisting when cooldown expires.</p>
          </div>
        </div>
        <div class={`text-[10px] font-black uppercase tracking-tighter ${autoUpdateEnabled() ? 'text-emerald-500' : 'text-gray-500'}`}>
          {autoUpdateEnabled() ? 'ENABLED' : 'DISABLED (ENABLE IN RISK SETTINGS)'}
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="bg-gray-800/50 border border-gray-700 rounded-lg p-5">
          <h4 class="text-xs font-black text-gray-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <div class="w-1.5 h-1.5 rounded-full bg-cyan-500"></div> System Detection
          </h4>
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <span class="text-xs font-bold text-gray-400">IPv4 Address</span>
              <span class="text-sm font-black font-mono text-white">{publicIpv4()}</span>
            </div>
            <Show when={publicIpv6() !== 'None'} fallback={
              <div class="flex items-center justify-between border-t border-gray-700 pt-3">
                <span class="text-xs font-bold text-gray-400">IPv6 Address</span>
                <span class="text-[10px] font-bold text-gray-600 uppercase">Not Detected</span>
              </div>
            }>
              <div class="flex items-center justify-between border-t border-gray-700 pt-3">
                <span class="text-xs font-bold text-gray-400">IPv6 Address</span>
                <span class="text-sm font-black font-mono text-white break-all text-right max-w-[200px]">{publicIpv6()}</span>
              </div>
            </Show>
          </div>
        </div>

        <div class="bg-gray-800/50 border border-gray-700 rounded-lg p-5">
          <h4 class="text-xs font-black text-gray-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <div class="w-1.5 h-1.5 rounded-full bg-primary-500"></div> Dhan Registered Slots
          </h4>
          <div class="space-y-4">
            <div class="space-y-2">
              <div class="flex items-center justify-between">
                <span class="text-xs font-bold text-gray-400 uppercase tracking-tighter">Primary Slot</span>
                <span class="text-sm font-black font-mono text-cyan-400">{registeredIps()?.primary_ip || 'Empty'}</span>
              </div>
              <Show when={registeredIps()?.modification_allowed_date_for_primary_ip}>
                <div class="flex items-center justify-between">
                  <span class="text-[9px] text-gray-500">Next Modification Allowed</span>
                  <div class="flex items-center gap-2">
                    <Show when={daysRemaining(registeredIps().modification_allowed_date_for_primary_ip) > 0}>
                      <span class="text-[9px] bg-amber-500/20 text-amber-500 px-1.5 py-0.5 rounded font-black">
                        IN {daysRemaining(registeredIps().modification_allowed_date_for_primary_ip)} DAYS
                      </span>
                    </Show>
                    <span class="text-[10px] font-black text-gray-400">{registeredIps().modification_allowed_date_for_primary_ip}</span>
                  </div>
                </div>
              </Show>
            </div>

            <div class="space-y-2 border-t border-gray-700 pt-3">
              <div class="flex items-center justify-between">
                <span class="text-xs font-bold text-gray-400 uppercase tracking-tighter">Secondary Slot</span>
                <span class="text-sm font-black font-mono text-cyan-400">{registeredIps()?.secondary_ip || 'Empty'}</span>
              </div>
              <Show when={registeredIps()?.modification_allowed_date_for_secondary_ip}>
                <div class="flex items-center justify-between">
                  <span class="text-[9px] text-gray-500">Next Modification Allowed</span>
                  <div class="flex items-center gap-2">
                    <Show when={daysRemaining(registeredIps().modification_allowed_date_for_secondary_ip) > 0}>
                      <span class="text-[9px] bg-amber-500/20 text-amber-500 px-1.5 py-0.5 rounded font-black">
                        IN {daysRemaining(registeredIps().modification_allowed_date_for_secondary_ip)} DAYS
                      </span>
                    </Show>
                    <span class="text-[10px] font-black text-gray-400">{registeredIps().modification_allowed_date_for_secondary_ip}</span>
                  </div>
                </div>
              </Show>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-gray-900/50 rounded-lg p-4 border border-dashed border-gray-800">
        <h5 class="text-[10px] font-black text-gray-600 uppercase tracking-[0.2em] mb-2">Static IP Compliance Note</h5>
        <p class="text-[10px] text-gray-500 leading-relaxed">
          Dhan enforces a 7-day cooldown period for IP whitelisting. If your ISP changes your public IP (dynamic IP), trading will be interrupted until whitelisted. Ensure your Airtel connection provides a Static IP for consistent performance.
        </p>
      </div>
    </div>
  )
}
