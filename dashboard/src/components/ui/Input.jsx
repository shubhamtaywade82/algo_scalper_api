import { Show } from 'solid-js'

export default function Input(props) {
  return (
    <div class="w-full">
      <Show when={props.label}>
        <label class="block text-sm font-medium text-gray-300 mb-1.5">{props.label}</label>
      </Show>
      <div class="relative">
        <Show when={props.leftAddon}>
          <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            {props.leftAddon}
          </div>
        </Show>
        <input
          class={`flex h-10 w-full rounded-md border bg-gray-800 px-3 py-2 text-sm text-gray-100 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-green-500 focus:border-transparent disabled:cursor-not-allowed disabled:opacity-50 ${props.leftAddon ? 'pl-10' : ''} ${props.rightAddon ? 'pr-10' : ''} ${props.error ? 'border-red-500 focus:ring-red-500' : 'border-gray-700'} ${props.class || ''}`}
          value={props.value}
          onInput={props.onInput}
          onChange={props.onChange}
          placeholder={props.placeholder}
          type={props.type || 'text'}
          disabled={props.disabled}
          min={props.min}
          max={props.max}
          step={props.step}
        />
        <Show when={props.rightAddon}>
          <div class="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
            {props.rightAddon}
          </div>
        </Show>
      </div>
      <Show when={props.error}>
        <p class="mt-1.5 text-sm text-red-400">{props.error}</p>
      </Show>
      <Show when={props.helperText && !props.error}>
        <p class="mt-1.5 text-sm text-gray-500">{props.helperText}</p>
      </Show>
    </div>
  )
}
