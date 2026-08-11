import { For, Show } from 'solid-js'
import { A } from '@solidjs/router'
import { navigationConfig } from '../../lib/config/routes'

// SVG icon mapping — avoids external icon dependency
const ICONS = {
  dashboard: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <rect width="20" height="16" x="2" y="4" rx="2" stroke-width="2"/>
      <path d="m7 10 2 2-2 2m5-2h5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  strategies: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  alpha: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="m12 3-1.912 5.886H3.886L9.088 12.5l-1.912 5.886L12 14.772l4.824 3.614-1.912-5.886 5.202-3.614h-6.202L12 3z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  signals: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  optionScalper: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M12 2v20M4 6h16M4 18h16M8 10h8v4H8z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  analysis: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M3 3v18h18M18.7 8l-5.1 5.2-2.8-2.7L7 14.3" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  marketWatch: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M2 12h1m18 0h1M12 2v1m0 18v1M4.22 4.22l.7.7m14.15-.7l-.7.7M4.22 19.78l.7-.7m14.15.7l-.7-.7" stroke-width="2" stroke-linecap="round"/>
      <circle cx="12" cy="12" r="5" stroke-width="2"/>
    </svg>
  ),
  optionChain: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M12 2v20M4 6h16M4 18h16M8 10h8v4H8z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  charts: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M3 3v18h18M7 16l4-8 4 4 4-6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  positions: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <rect width="18" height="14" x="3" y="5" rx="2" stroke-width="2"/>
      <path d="M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z" stroke-width="2"/>
    </svg>
  ),
  ledger: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M8 7h8M8 11h8M8 15h4" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ),
  holdings: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="10" stroke-width="2"/>
      <path d="M12 6v6l4 2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  funds: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <rect width="20" height="14" x="2" y="5" rx="2" stroke-width="2"/>
      <path d="M12 10v4M10 12h4" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ),
  reports: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M14 2v6h6M16 13H8M16 17H8M10 9H8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  logs: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" stroke-width="2" stroke-linecap="round"/>
      <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" stroke-width="2" stroke-linecap="round"/>
      <path d="M8 6h8M8 10h8M8 14h4" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ),
  alerts: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M13.73 21a2 2 0 0 1-3.46 0" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ),
  scheduler: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <rect width="18" height="18" x="3" y="4" rx="2" stroke-width="2"/>
      <path d="M16 2v4M8 2v4M3 10h18" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ),
  settings: () => (
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.1a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <circle cx="12" cy="12" r="3" stroke-width="2"/>
    </svg>
  ),
}

function NavItem(props) {
  const Icon = ICONS[props.item.icon]
  return (
    <A
      href={props.item.href}
      end={props.item.end}
      title={props.collapsed ? props.item.label : undefined}
      class={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs font-black uppercase tracking-widest transition-all duration-200 group ${props.collapsed ? 'justify-center px-0' : ''}`}
      activeClass="bg-primary-500/15 text-primary-300 border border-primary-500/25 shadow-[0_0_15px_rgba(59,130,246,0.1)]"
      inactiveClass="text-gray-500 hover:text-gray-300 hover:bg-white/[0.03] border border-transparent"
    >
      <span class="shrink-0 w-5 h-5 flex items-center justify-center">
        {Icon && <Icon />}
      </span>
      <Show when={!props.collapsed}>
        <span class="truncate">{props.item.label}</span>
      </Show>
    </A>
  )
}

export default function Sidebar(props) {
  const collapsed = () => props.collapsed

  return (
    <aside class={`sticky top-0 h-screen shrink-0 bg-gray-900/80 backdrop-blur-xl border-r border-white/5 transition-all duration-300 z-40 flex flex-col justify-between ${collapsed() ? 'w-16' : 'w-56'}`}>
      <div class="flex-1 overflow-y-auto overflow-x-hidden p-2 space-y-4 scrollbar-thin">
        <For each={navigationConfig}>
          {(section, i) => (
            <div>
              <Show when={!collapsed()} fallback={<Show when={i() > 0}><div class="mx-3 mb-2 border-t border-white/5" /></Show>}>
                <div class="px-3 py-1.5 text-[8px] font-black text-gray-500 uppercase tracking-[0.2em]">
                  {section.section.label}
                </div>
              </Show>
              <div class="space-y-0.5">
                <For each={section.items}>
                  {(item) => (
                    <NavItem item={item} collapsed={collapsed()} />
                  )}
                </For>
              </div>
            </div>
          )}
        </For>
      </div>
    </aside>
  )
}
