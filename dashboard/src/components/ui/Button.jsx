import { Show } from 'solid-js'

const variants = {
  default: 'bg-green-600 text-white hover:bg-green-700',
  destructive: 'bg-red-600 text-white hover:bg-red-700',
  outline: 'border border-gray-700 hover:bg-gray-800',
  secondary: 'bg-gray-800 text-gray-100 hover:bg-gray-700',
  ghost: 'hover:bg-gray-800',
  link: 'underline-offset-4 hover:underline text-green-500',
}

const sizes = {
  default: 'h-10 py-2 px-4',
  sm: 'h-9 px-3',
  lg: 'h-11 px-8',
  icon: 'h-10 w-10',
}

export default function Button(props) {
  const variant = () => props.variant || 'default'
  const size = () => props.size || 'default'
  const loading = () => props.loading

  return (
    <button
      class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none ${variants[variant()]} ${sizes[size()]} ${props.class || ''}`}
      disabled={loading() || props.disabled}
      onClick={props.onClick}
      {...props.attrs}
    >
      <Show when={loading()}>
        <span class="mr-2 h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
      </Show>
      <Show when={!loading() && props.leftIcon}>
        <span class="mr-2">{props.leftIcon}</span>
      </Show>
      {props.children}
      <Show when={!loading() && props.rightIcon}>
        <span class="ml-2">{props.rightIcon}</span>
      </Show>
    </button>
  )
}
