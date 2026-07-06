import { For } from 'solid-js'

export default function ParametersTable(props) {
  function updateParam(index, field, value) {
    const updated = props.parameters().map((p, i) => {
      if (i === index) return { ...p, [field]: value }
      return { ...p }
    })
    props.onChange(updated)
  }

  function addParam() {
    const updated = [
      ...props.parameters(),
      { name: '', type: 'Integer', default_value: '', description: '' },
    ]
    props.onChange(updated)
  }

  function removeParam(index) {
    const updated = props.parameters().filter((_, i) => i !== index)
    props.onChange(updated)
  }

  return (
    <div class="flex flex-col gap-3">
      <div class="flex items-center justify-between">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Parameters</span>
        <button
          onClick={addParam}
          class="text-[10px] font-bold text-primary-400 hover:text-primary-300 transition flex items-center gap-1"
        >
          <svg class="w-3 h-3" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
          </svg>
          Add
        </button>
      </div>

      {/* Table header */}
      <div class="grid grid-cols-[1fr_80px_70px_1fr_28px] gap-1.5 text-[9px] font-black text-gray-600 uppercase tracking-widest px-1">
        <span>Name</span>
        <span>Type</span>
        <span>Default</span>
        <span>Description</span>
        <span />
      </div>

      {/* Table rows */}
      <div class="flex flex-col gap-1.5 max-h-[240px] overflow-y-auto">
        <For each={props.parameters()}>
          {(param, index) => (
            <div class="grid grid-cols-[1fr_80px_70px_1fr_28px] gap-1.5 items-center group">
              <input
                value={param.name}
                onInput={(e) => updateParam(index(), 'name', e.target.value)}
                placeholder="name"
                class="bg-white/5 border border-white/10 rounded-lg px-2 py-1.5 text-[11px] text-gray-200 focus:border-primary-500/50 outline-none transition"
              />
              <select
                value={param.type}
                onChange={(e) => updateParam(index(), 'type', e.target.value)}
                class="glass-select rounded-lg px-1.5 py-1.5 text-[11px] cursor-pointer"
              >
                <option value="Integer">Integer</option>
                <option value="Float">Float</option>
                <option value="String">String</option>
                <option value="Boolean">Boolean</option>
              </select>
              <input
                value={param.default_value}
                onInput={(e) => updateParam(index(), 'default_value', e.target.value)}
                placeholder="value"
                class="bg-white/5 border border-white/10 rounded-lg px-2 py-1.5 text-[11px] text-gray-200 focus:border-primary-500/50 outline-none transition"
              />
              <input
                value={param.description}
                onInput={(e) => updateParam(index(), 'description', e.target.value)}
                placeholder="description"
                class="bg-white/5 border border-white/10 rounded-lg px-2 py-1.5 text-[11px] text-gray-300 focus:border-primary-500/50 outline-none transition"
              />
              <button
                onClick={() => removeParam(index())}
                class="w-6 h-6 flex items-center justify-center rounded-lg text-gray-600 hover:text-rose-400 hover:bg-rose-500/10 transition opacity-0 group-hover:opacity-100"
                title="Remove parameter"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                </svg>
              </button>
            </div>
          )}
        </For>
      </div>

      {/* Empty state */}
      {props.parameters().length === 0 && (
        <div class="text-center py-4 text-[11px] text-gray-600">
          No parameters defined. Click <span class="text-primary-400">+Add</span> to add one.
        </div>
      )}
    </div>
  )
}
