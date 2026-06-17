import { createMemo } from 'solid-js'
import {
  useAnimatedNumber,
  formatAnimatedNumber,
  animatedSign,
  pnlTextClass,
} from '../lib/useAnimatedNumber'

export default function AnimatedNumber(props) {
  const animated = useAnimatedNumber(
    () => props.value,
    { duration: props.duration },
  )

  const colorClass = createMemo(() => {
    if (!props.pnlColor) return ''
    const tone = pnlTextClass(animated(), { zeroPositive: props.zeroPositive ?? false })
    return `${tone} transition-colors duration-300`
  })

  const mergedClass = createMemo(() => [props.class, colorClass()].filter(Boolean).join(' '))

  const formatted = createMemo(() => {
    if (props.format) return props.format(animated())

    const absolute = props.absolute ?? (props.showSign ? true : false)

    return formatAnimatedNumber(animated(), {
      decimals: props.decimals ?? 2,
      absolute,
      integer: props.integer ?? false,
      nullDisplay: props.nullDisplay ?? '—',
    })
  })

  const sign = createMemo(() => {
    if (!props.showSign && !props.signOnly) return ''
    return animatedSign(animated())
  })

  if (props.signOnly) {
    return <span class={mergedClass()}>{sign()}</span>
  }

  return (
    <span class={mergedClass()}>
      {sign()}{props.prefix ?? ''}{props.currency ? '₹' : ''}{formatted()}{props.suffix ?? ''}
    </span>
  )
}
