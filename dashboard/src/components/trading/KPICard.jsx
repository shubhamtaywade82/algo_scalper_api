import { Show } from 'solid-js'
import { Card, CardHeader, CardContent, CardFooter } from '../ui/Card'

function TrendBadge(props) {
  const colors = {
    positive: 'text-green-400',
    negative: 'text-red-400',
    neutral: 'text-gray-400',
  }

  const icons = {
    positive: '▲',
    negative: '▼',
    neutral: '—',
  }

  const type = () => {
    const t = props.type
    if (t) return t
    const val = Number(props.value)
    return val > 0 ? 'positive' : val < 0 ? 'negative' : 'neutral'
  }

  return (
    <span class={`text-sm font-medium inline-flex items-center gap-0.5 ${colors[type()]} ${props.class || ''}`}>
      <Show when={props.showIcon}>
        <span>{icons[type()]}</span>
      </Show>
      {typeof props.value === 'number' ? `${props.value >= 0 ? '+' : ''}${props.value}%` : props.value}
    </span>
  )
}

export { TrendBadge }

export default function KPICard(props) {
  const trendType = () => {
    const t = props.trend?.type
    if (t) return t
    const v = Number(props.trend?.value)
    return v > 0 ? 'positive' : v < 0 ? 'negative' : 'neutral'
  }

  return (
    <Card class={`relative overflow-hidden ${props.class || ''}`}>
      <CardHeader>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <Show when={props.icon}>
              <span class="text-gray-400">{props.icon}</span>
            </Show>
            <span class="text-sm font-medium text-gray-400">{props.title}</span>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <Show when={props.loading} fallback={
          <div class="flex items-end justify-between">
            <div>
              <div class="text-2xl font-bold text-gray-100">
                {props.formattedValue || props.value}
              </div>
              <Show when={props.trend}>
                <div class="mt-1">
                  <TrendBadge
                    value={props.trend.formattedValue || props.trend.value}
                    type={trendType()}
                    showIcon
                  />
                </div>
              </Show>
            </div>
          </div>
        }>
          <div class="h-8 w-32 bg-gray-800 rounded animate-pulse" />
        </Show>
      </CardContent>
      <Show when={props.footer}>
        <CardFooter class="text-xs text-gray-500">
          {props.footer}
        </CardFooter>
      </Show>
    </Card>
  )
}
