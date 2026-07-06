import { Show } from 'solid-js'

export default function PageContainer(props) {
  const paddingClasses = {
    none: '',
    sm: 'p-4',
    md: 'p-6',
    lg: 'p-8',
  }

  const padding = () => paddingClasses[props.padding] || paddingClasses.md

  return (
    <div class={`flex-1 min-h-screen ${padding()}`}>
      <Show when={props.title}>
        <div class="mb-6 flex items-start justify-between">
          <div>
            <h1 class="text-2xl font-bold text-gray-100">{props.title}</h1>
            <Show when={props.subtitle}>
              <p class="text-sm text-gray-400 mt-1">{props.subtitle}</p>
            </Show>
          </div>
          <Show when={props.actions}>
            <div class="flex gap-2">{props.actions}</div>
          </Show>
        </div>
      </Show>
      {props.children}
    </div>
  )
}
