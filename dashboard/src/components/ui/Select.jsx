import { Show, For } from 'solid-js'

export default function Select(props) {
  return (
    <div class="w-full">
      <Show when={props.label}>
        <label class="block text-sm font-medium text-gray-300 mb-1.5">{props.label}</label>
      </Show>
      <select
        class={`flex h-10 w-full rounded-md border bg-gray-800 px-3 py-2 text-sm text-gray-100 focus:outline-none focus:ring-2 focus:ring-green-500 focus:border-transparent disabled:cursor-not-allowed disabled:opacity-50 ${props.error ? 'border-red-500 focus:ring-red-500' : 'border-gray-700'} ${props.class || ''}`}
        value={props.value}
        onChange={props.onChange}
        disabled={props.disabled}
      >
        <Show when={props.placeholder}>
          <option value="" disabled>{props.placeholder}</option>
        </Show>
        <For each={props.options || []}>
          {(opt) => (
            <option value={opt.value} disabled={opt.disabled}>
              {opt.label}
            </option>
          )}
        </For>
      </select>
      <Show when={props.error}>
        <p class="mt-1.5 text-sm text-red-400">{props.error}</p>
      </Show>
      <Show when={props.helperText && !props.error}>
        <p class="mt-1.5 text-sm text-gray-500">{props.helperText}</p>
      </Show>
    </div>
  )
}
