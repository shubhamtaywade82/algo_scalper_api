import { Show } from 'solid-js'

export default function Modal(props) {
  const show = () => props.show
  const size = () => props.size || 'md'

  const sizes = {
    sm: 'max-w-md',
    md: 'max-w-2xl',
    lg: 'max-w-4xl',
    xl: 'max-w-6xl',
    full: 'max-w-[95vw] w-full',
  }

  return (
    <Show when={show()}>
      <div class="fixed inset-0 z-50 flex items-center justify-center">
        <div class="fixed inset-0 bg-black/80 backdrop-blur-sm" onClick={props.onClose} />
        <div class={`relative z-50 w-full ${sizes[size()]} border border-gray-800 bg-gray-900 shadow-lg rounded-lg max-h-[85vh] overflow-y-auto`}>
          <div class="flex items-center justify-between px-6 py-4 border-b border-gray-800">
            <h3 class="text-lg font-semibold text-gray-100">{props.title}</h3>
            <button onClick={props.onClose} class="text-gray-400 hover:text-gray-100 transition-colors">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path d="M18 6L6 18M6 6l12 12" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </button>
          </div>
          <div class="p-6">
            {props.children}
          </div>
        </div>
      </div>
    </Show>
  )
}
