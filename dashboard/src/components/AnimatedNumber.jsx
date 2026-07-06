import { createSignal, createMemo, createEffect } from 'solid-js'
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

  const [flashClass, setFlashClass] = createSignal('')
  let prevVal = props.value
  let flashTimeout = null

  createEffect(() => {
    const newVal = props.value
    const oldVal = prevVal

    if (oldVal !== undefined && oldVal !== null && newVal !== oldVal && Number.isFinite(Number(newVal)) && Number.isFinite(Number(oldVal))) {
      if (flashTimeout) clearTimeout(flashTimeout)
      const direction = Number(newVal) > Number(oldVal) ? 'price-up' : 'price-down'
      setFlashClass(direction)
      flashTimeout = setTimeout(() => {
        setFlashClass('')
        flashTimeout = null
      }, 1000)
    }
    prevVal = newVal
  })

  const colorClass = createMemo(() => {
    if (!props.pnlColor) return ''
    const tone = pnlTextClass(animated(), { zeroPositive: props.zeroPositive ?? false })
    return `${tone} transition-colors duration-300`
  })

  const mergedClass = createMemo(() => [props.class, colorClass(), flashClass()].filter(Boolean).join(' '))

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
