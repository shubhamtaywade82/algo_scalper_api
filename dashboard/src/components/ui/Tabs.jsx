import { createSignal, For, Show } from 'solid-js'

export function Tabs(props) {
  const [activeTab, setActiveTab] = createSignal(props.defaultValue || (props.tabs?.[0]?.value))

  const currentTab = () => props.value ?? activeTab()
  const onTabChange = (value) => {
    setActiveTab(value)
    props.onChange?.(value)
  }

  const activeContent = () => {
    const tab = (props.tabs || []).find(t => t.value === currentTab())
    return tab?.children || tab?.content
  }

  return (
    <div class={props.class || ''}>
      <div class={`flex border-b border-white/5 ${props.tabBarClass || ''}`}>
        <For each={props.tabs || []}>
          {(tab) => (
            <button
              onClick={() => onTabChange(tab.value)}
              disabled={tab.disabled}
              class={`px-4 py-2.5 text-sm font-medium transition-colors relative ${
                tab.disabled ? 'opacity-40 cursor-not-allowed' : 'cursor-pointer'
              } ${
                currentTab() === tab.value
                  ? 'text-green-400'
                  : 'text-gray-500 hover:text-gray-300'
              } ${props.tabClass || ''}`}
            >
              {tab.label}
              <Show when={currentTab() === tab.value}>
                <div class="absolute bottom-0 left-0 right-0 h-0.5 bg-green-500 rounded-full" />
              </Show>
            </button>
          )}
        </For>
      </div>
      <Show when={props.children} keyed>
        <div class={props.contentClass || 'mt-4'}>
          {props.children}
        </div>
      </Show>
      <Show when={!props.children && activeContent()}>
        <div class={props.contentClass || 'mt-4'}>
          {activeContent()}
        </div>
      </Show>
    </div>
  )
}

export function TabPanel(props) {
  return (
    <Show when={props.value === props.activeTab}>
      <div class={props.class || ''}>
        {props.children}
      </div>
    </Show>
  )
}
