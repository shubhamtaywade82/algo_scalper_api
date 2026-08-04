import { For, createSignal } from 'solid-js'

export default function ParametersTable(props) {
  const params = () => props.parameters() || []

  const updateParam = (index, key, value) => {
    const updated = [...params()]
    updated[index] = { ...updated[index], [key]: value }
    props.onChange(updated)
  }

  const addParam = () => {
    const updated = [...params(), { name: 'new_param', type: 'Integer', default_value: '0', description: 'Parameter description' }]
    props.onChange(updated)
  }

  const removeParam = (index) => {
    const updated = params().filter((_, i) => i !== index)
    props.onChange(updated)
  }

  return (
    <div class="space-y-2">
      <div class="flex items-center justify-between">
        <span class="text-[10px] font-black text-gray-400 uppercase tracking-wider">Parameters</span>
        <button
          onClick={addParam}
          class="px-2 py-0.5 bg-primary-600/20 border border-primary-500/30 hover:bg-primary-600/30 text-primary-400 text-[9px] font-black uppercase tracking-wider rounded-md transition-all"
        >
          + Add
        </button>
      </div>

      <div class="glass border border-white/5 rounded-xl overflow-hidden">
        <table class="w-full text-[10px] text-left border-collapse">
          <thead>
            <tr class="bg-white/[0.02] border-b border-white/5 text-gray-500 font-black uppercase">
              <th class="px-3 py-2 w-1/4">Name</th>
              <th class="px-3 py-2 w-1/5">Type</th>
              <th class="px-3 py-2 w-1/5">Default</th>
              <th class="px-3 py-2 w-1/3">Description</th>
              <th class="px-2 py-2 w-8"></th>
            </tr>
          </thead>
          <tbody>
            <For each={params()}>
              {(p, i) => (
                <tr class="border-b border-white/[0.02] hover:bg-white/[0.01]">
                  <td class="px-2 py-1.5">
                    <input
                      type="text"
                      value={p.name}
                      onInput={(e) => updateParam(i(), 'name', e.target.value)}
                      class="w-full bg-transparent outline-none border-none text-white font-mono p-0 focus:ring-0 text-[10px]"
                    />
                  </td>
                  <td class="px-2 py-1.5">
                    <select
                      value={p.type}
                      onChange={(e) => updateParam(i(), 'type', e.target.value)}
                      class="w-full bg-transparent outline-none border-none text-primary-400 p-0 focus:ring-0 text-[10px] cursor-pointer"
                    >
                      <option value="Integer">Integer</option>
                      <option value="Float">Float</option>
                      <option value="String">String</option>
                      <option value="Boolean">Boolean</option>
                    </select>
                  </td>
                  <td class="px-2 py-1.5">
                    <input
                      type="text"
                      value={p.default_value}
                      onInput={(e) => updateParam(i(), 'default_value', e.target.value)}
                      class="w-full bg-transparent outline-none border-none text-gray-300 font-mono p-0 focus:ring-0 text-[10px]"
                    />
                  </td>
                  <td class="px-2 py-1.5">
                    <input
                      type="text"
                      value={p.description}
                      onInput={(e) => updateParam(i(), 'description', e.target.value)}
                      class="w-full bg-transparent outline-none border-none text-gray-500 p-0 focus:ring-0 text-[10px]"
                    />
                  </td>
                  <td class="px-2 py-1.5 text-center">
                    <button
                      onClick={() => removeParam(i())}
                      class="text-rose-400 hover:text-rose-300 text-xs font-black"
                    >
                      ×
                    </button>
                  </td>
                </tr>
              )}
            </For>
          </tbody>
        </table>
        {params().length === 0 && (
          <div class="p-4 text-center text-gray-600 uppercase tracking-widest text-[9px]">
            No parameters defined
          </div>
        )}
      </div>
    </div>
  )
}
