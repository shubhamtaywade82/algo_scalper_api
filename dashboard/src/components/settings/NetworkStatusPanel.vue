<script setup>
import { computed, inject } from 'vue'

const { publicIpv4, publicIpv6, registeredIps } = inject('dashboardState')

const isIpVerified = computed(() => {
  if (!registeredIps?.value) return false
  const registered = [
    registeredIps.value.primary_ip,
    registeredIps.value.secondary_ip
  ].filter(Boolean)
  
  return registered.includes(publicIpv4.value) || (publicIpv6.value !== 'None' && registered.includes(publicIpv6.value))
})

function daysRemaining(dateStr) {
  if (!dateStr) return null
  const target = new Date(dateStr)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  target.setHours(0, 0, 0, 0)
  
  const diffTime = target - today
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))
  return diffDays > 0 ? diffDays : 0
}
</script>

<template>
  <div class="space-y-6">
    <!-- Status Header -->
    <div :class="['p-4 rounded-lg border flex items-center justify-between', isIpVerified ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400' : 'bg-amber-500/10 border-amber-500/20 text-amber-400']">
      <div class="flex items-center gap-3">
        <div :class="['w-10 h-10 rounded-full flex items-center justify-center', isIpVerified ? 'bg-emerald-500/20' : 'bg-amber-500/20']">
          <svg v-if="isIpVerified" xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
          <svg v-else xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
        </div>
        <div>
          <h3 class="font-bold uppercase tracking-wider">{{ isIpVerified ? 'Verified Static IP' : 'Unregistered Identity' }}</h3>
          <p class="text-xs opacity-70">{{ isIpVerified ? 'Your current network identity matches Dhan whitelisted slots.' : 'Current IP is not registered on Dhan. Automated orders will fail.' }}</p>
        </div>
      </div>
      <div class="text-right">
        <span class="text-[10px] font-black uppercase tracking-widest opacity-50 block mb-1">Dhan Compliance</span>
        <div :class="['px-3 py-1 rounded-full text-[10px] font-black uppercase border', isIpVerified ? 'border-emerald-500/30' : 'border-amber-500/30']">
          {{ isIpVerified ? 'GATE OPEN' : 'GATE CLOSED' }}
        </div>
      </div>
    </div>

    <!-- IP Details Grid -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <!-- Current Detection -->
      <div class="bg-gray-800/50 border border-gray-700 rounded-lg p-5">
        <h4 class="text-xs font-black text-gray-500 uppercase tracking-widest mb-4 flex items-center gap-2">
          <div class="w-1.5 h-1.5 rounded-full bg-cyan-500"></div> System Detection
        </h4>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <span class="text-xs font-bold text-gray-400">IPv4 Address</span>
            <span class="text-sm font-black font-mono text-white">{{ publicIpv4 }}</span>
          </div>
          <div v-if="publicIpv6 !== 'None'" class="flex items-center justify-between border-t border-gray-700 pt-3">
            <span class="text-xs font-bold text-gray-400">IPv6 Address</span>
            <span class="text-sm font-black font-mono text-white break-all text-right max-w-[200px]">{{ publicIpv6 }}</span>
          </div>
          <div v-else class="flex items-center justify-between border-t border-gray-700 pt-3">
            <span class="text-xs font-bold text-gray-400">IPv6 Address</span>
            <span class="text-[10px] font-bold text-gray-600 uppercase">Not Detected</span>
          </div>
        </div>
      </div>

      <!-- Registered Slots -->
      <div class="bg-gray-800/50 border border-gray-700 rounded-lg p-5">
        <h4 class="text-xs font-black text-gray-500 uppercase tracking-widest mb-4 flex items-center gap-2">
          <div class="w-1.5 h-1.5 rounded-full bg-primary-500"></div> Dhan Registered Slots
        </h4>
        <div class="space-y-4">
          <!-- Primary Slot -->
          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-bold text-gray-400 uppercase tracking-tighter">Primary Slot</span>
              <span class="text-sm font-black font-mono text-cyan-400">{{ registeredIps?.primary_ip || 'Empty' }}</span>
            </div>
            <div v-if="registeredIps?.modification_allowed_date_for_primary_ip" class="flex items-center justify-between">
              <span class="text-[9px] text-gray-500">Next Modification Allowed</span>
              <div class="flex items-center gap-2">
                <span v-if="daysRemaining(registeredIps.modification_allowed_date_for_primary_ip) > 0" class="text-[9px] bg-amber-500/20 text-amber-500 px-1.5 py-0.5 rounded font-black">
                  IN {{ daysRemaining(registeredIps.modification_allowed_date_for_primary_ip) }} DAYS
                </span>
                <span class="text-[10px] font-black text-gray-400">{{ registeredIps.modification_allowed_date_for_primary_ip }}</span>
              </div>
            </div>
          </div>

          <!-- Secondary Slot -->
          <div class="space-y-2 border-t border-gray-700 pt-3">
            <div class="flex items-center justify-between">
              <span class="text-xs font-bold text-gray-400 uppercase tracking-tighter">Secondary Slot</span>
              <span class="text-sm font-black font-mono text-cyan-400">{{ registeredIps?.secondary_ip || 'Empty' }}</span>
            </div>
            <div v-if="registeredIps?.modification_allowed_date_for_secondary_ip" class="flex items-center justify-between">
              <span class="text-[9px] text-gray-500">Next Modification Allowed</span>
              <div class="flex items-center gap-2">
                <span v-if="daysRemaining(registeredIps.modification_allowed_date_for_secondary_ip) > 0" class="text-[9px] bg-amber-500/20 text-amber-500 px-1.5 py-0.5 rounded font-black">
                  IN {{ daysRemaining(registeredIps.modification_allowed_date_for_secondary_ip) }} DAYS
                </span>
                <span class="text-[10px] font-black text-gray-400">{{ registeredIps.modification_allowed_date_for_secondary_ip }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Audit Footer -->
    <div class="bg-gray-900/50 rounded-lg p-4 border border-dashed border-gray-800">
      <h5 class="text-[10px] font-black text-gray-600 uppercase tracking-[0.2em] mb-2">Static IP Compliance Note</h5>
      <p class="text-[10px] text-gray-500 leading-relaxed">
        Dhan enforces a 7-day cooldown period for IP whitelisting. If your ISP changes your public IP (dynamic IP), trading will be interrupted until whitelisted. Ensure your Airtel connection provides a Static IP for consistent performance.
      </p>
    </div>
  </div>
</template>
