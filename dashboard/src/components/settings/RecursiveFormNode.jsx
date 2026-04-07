import { For, Show } from 'solid-js'

export default function RecursiveFormNode(props) {
  const node = () => props.node

  function handleArrayUpdate(index, newValue) {
    const newArray = [...node()]
    newArray[index] = newValue
    props.onUpdate?.(newArray)
  }

  function handleObjectUpdate(key, newValue) {
    const newObj = { ...node() }
    newObj[key] = newValue
    props.onUpdate?.(newObj)
  }

  return (
    <div class="space-y-4">
      <Show when={Array.isArray(node())}>
        <For each={node()}>
          {(item, getIndex) => (
            <div class="p-4 bg-gray-950 border border-gray-800 rounded-lg mb-4">
              <div class="flex justify-between items-center mb-4 border-b border-gray-800 pb-2">
                <span class="text-xs font-black text-gray-500 uppercase tracking-widest">
                  Item {getIndex() + 1} {item.key ? `(${item.key})` : ''}
                </span>
              </div>
              <Show
                when={typeof item === 'object' && item !== null}
                fallback={
                  <div class="flex items-center gap-4">
                    <input
                      type="text"
                      value={item}
                      onInput={(e) => handleArrayUpdate(getIndex(), e.target.value)}
                      class="flex-1 bg-gray-900 border border-gray-700 rounded p-2 text-sm text-gray-200"
                    />
                  </div>
                }
              >
                <RecursiveFormNode node={item} onUpdate={(val) => handleArrayUpdate(getIndex(), val)} />
              </Show>
            </div>
          )}
        </For>
      </Show>

      <Show when={!Array.isArray(node()) && typeof node() === 'object' && node() !== null}>
        <For each={Object.entries(node() || {})}>
          {([key, val]) => (
            <div class="border-b border-gray-800/50 pb-4 last:border-0">
              <div class="flex flex-col md:flex-row md:items-start justify-between gap-4 mt-2">
                <div class="md:w-1/3 pt-1 text-sm font-semibold text-gray-300 capitalize">
                  {String(key).replace(/_/g, ' ')}
                </div>
                <div class="md:w-2/3">
                  <Show when={typeof val === 'boolean'}>
                    <div class="relative inline-block w-12 align-middle select-none">
                      <input
                        type="checkbox"
                        checked={val}
                        onChange={(e) => handleObjectUpdate(key, e.target.checked)}
                        class={`toggle-checkbox absolute block w-6 h-6 rounded-full bg-white border-4 appearance-none cursor-pointer transition-transform duration-200 ease-in-out ${val ? 'translate-x-6 border-cyan-500' : 'translate-x-0 border-gray-600'}`}
                      />
                      <label
                        class={`toggle-label block overflow-hidden h-6 rounded-full cursor-pointer transition-colors duration-200 ease-in-out ${val ? 'bg-cyan-600' : 'bg-gray-800 border box-content border-gray-600'}`}
                        onClick={() => handleObjectUpdate(key, !val)}
                      ></label>
                    </div>
                  </Show>
                  <Show when={typeof val === 'number'}>
                    <input
                      type="number"
                      value={val}
                      onInput={(e) => handleObjectUpdate(key, Number(e.target.value))}
                      class="bg-gray-950 border border-gray-700 text-gray-200 text-sm rounded focus:ring-1 focus:ring-cyan-500 outline-none block p-2"
                      style={{ 'max-width': '150px' }}
                    />
                  </Show>
                  <Show when={typeof val === 'string'}>
                    <input
                      type="text"
                      value={val}
                      onInput={(e) => handleObjectUpdate(key, e.target.value)}
                      class="w-full bg-gray-950 border border-gray-700 text-gray-200 text-sm rounded focus:ring-1 focus:ring-cyan-500 outline-none block p-2"
                    />
                  </Show>
                  <Show when={typeof val === 'object' && val !== null}>
                    <div class="pl-4 border-l-2 border-gray-800 mt-2">
                      <RecursiveFormNode node={val} onUpdate={(newVal) => handleObjectUpdate(key, newVal)} />
                    </div>
                  </Show>
                </div>
              </div>
            </div>
          )}
        </For>
      </Show>
    </div>
  )
}
