import { Show } from 'solid-js'

export default function Toggle(props) {
  const checked = () => props.checked ?? false

  return (
    <div class={`inline-flex items-center ${props.class || ''}`}>
      <Show when={props.label}>
        <span class="text-sm font-medium text-gray-300 mr-3">{props.label}</span>
      </Show>
      <button
        role="switch"
        aria-checked={checked()}
        onClick={() => props.onChange?.(!checked())}
        disabled={props.disabled}
        class={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500 focus-visible:ring-offset-2 focus-visible:ring-offset-gray-900 disabled:cursor-not-allowed disabled:opacity-50 ${
          checked() ? 'bg-green-600' : 'bg-gray-700'
        }`}
      >
        <span
          class={`pointer-events-none block h-4 w-4 rounded-full bg-white shadow-lg transform transition-transform ${
            checked() ? 'translate-x-4' : 'translate-x-0'
          }`}
        />
      </button>
      <Show when={props.helpText}>
        <span class="text-xs text-gray-500 ml-2">{props.helpText}</span>
      </Show>
    </div>
  )
}
