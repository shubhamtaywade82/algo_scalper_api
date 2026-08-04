import { createSignal } from 'solid-js'

const positions = {
  top: 'bottom-full left-1/2 -translate-x-1/2 mb-2',
  bottom: 'top-full left-1/2 -translate-x-1/2 mt-2',
  left: 'right-full top-1/2 -translate-y-1/2 mr-2',
  right: 'left-full top-1/2 -translate-y-1/2 ml-2',
}

const arrows = {
  top: 'top-full left-1/2 -translate-x-1/2 border-l-transparent border-r-transparent border-b-transparent border-t-gray-800',
  bottom: 'bottom-full left-1/2 -translate-x-1/2 border-l-transparent border-r-transparent border-t-transparent border-b-gray-800',
  left: 'left-full top-1/2 -translate-y-1/2 border-t-transparent border-b-transparent border-r-transparent border-l-gray-800',
  right: 'right-full top-1/2 -translate-y-1/2 border-t-transparent border-b-transparent border-l-transparent border-r-gray-800',
}

export default function Tooltip(props) {
  const position = () => props.position || 'top'
  const showDelay = () => props.showDelay ?? 300
  const hideDelay = () => props.hideDelay ?? 100
  const [visible, setVisible] = createSignal(false)

  let openTimer
  let closeTimer

  function show() {
    clearTimeout(closeTimer)
    openTimer = setTimeout(() => setVisible(true), showDelay())
  }

  function hide() {
    clearTimeout(openTimer)
    closeTimer = setTimeout(() => setVisible(false), hideDelay())
  }

  return (
    <div class={`relative inline-flex ${props.class || ''}`} onMouseEnter={show} onMouseLeave={hide}>
      {props.children}
      <div
        class={`absolute z-50 ${positions[position()]} ${
          visible() ? 'opacity-100 visible' : 'opacity-0 invisible'
        } transition-opacity duration-150`}
        role="tooltip"
      >
        <div class="bg-gray-800 text-gray-100 text-xs rounded-md px-3 py-1.5 shadow-lg border border-gray-700 whitespace-nowrap">
          {props.content || props.label}
        </div>
        <div class={`absolute w-0 h-0 border-4 ${arrows[position()]}`} />
      </div>
    </div>
  )
}

export function SimpleTooltip(props) {
  return (
    <span
      title={props.label || props.content}
      class={`relative cursor-help border-b border-dotted border-gray-600 ${props.class || ''}`}
    >
      {props.children}
    </span>
  )
}
