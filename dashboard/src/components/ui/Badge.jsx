import { Show } from 'solid-js'

const variantClasses = {
  default: 'border-transparent bg-gray-800 text-gray-100',
  secondary: 'border-transparent bg-gray-700 text-gray-200',
  success: 'border-transparent bg-green-900/50 text-green-400',
  danger: 'border-transparent bg-red-900/50 text-red-400',
  warning: 'border-transparent bg-yellow-900/50 text-yellow-400',
  info: 'border-transparent bg-blue-900/50 text-blue-400',
  outline: 'border-gray-700 text-gray-400',
}

const dotColors = {
  green: 'bg-green-400',
  red: 'bg-red-400',
  yellow: 'bg-yellow-400',
  blue: 'bg-blue-400',
}

export default function Badge(props) {
  const variant = () => props.variant || 'default'
  const dotColor = () => props.dotColor || 'green'

  return (
    <div class={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none ${variantClasses[variant()]} ${props.class || ''}`}>
      <Show when={props.dot}>
        <span class={`mr-1.5 h-1.5 w-1.5 rounded-full ${dotColors[dotColor()]}`} />
      </Show>
      {props.children}
    </div>
  )
}
