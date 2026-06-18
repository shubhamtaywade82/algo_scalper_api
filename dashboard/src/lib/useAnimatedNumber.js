import { createSignal, createEffect, onCleanup } from 'solid-js'

const DEFAULT_DURATION_MS = 450

function easeOutCubic(t) {
  return 1 - (1 - t) ** 3
}

function parseTarget(raw) {
  if (raw == null || raw === '') return null
  const n = Number(raw)
  return Number.isFinite(n) ? n : null
}

export function useAnimatedNumber(getValue, options = {}) {
  const duration = () => options.duration ?? DEFAULT_DURATION_MS
  const [display, setDisplay] = createSignal(0)

  let current = null
  let rafId = null

  createEffect(() => {
    const target = parseTarget(getValue())

    if (target === null) {
      if (rafId) {
        cancelAnimationFrame(rafId)
        rafId = null
      }
      current = null
      setDisplay(NaN)
      return
    }

    if (current === null) {
      current = target
      setDisplay(target)
      return
    }

    if (Math.abs(target - current) < 1e-9) return

    const from = current
    const to = target
    let startTime = null

    if (rafId) cancelAnimationFrame(rafId)

    const tick = (timestamp) => {
      if (startTime === null) startTime = timestamp

      const progress = Math.min((timestamp - startTime) / duration(), 1)
      const next = from + (to - from) * easeOutCubic(progress)
      current = next
      setDisplay(next)

      if (progress < 1) {
        rafId = requestAnimationFrame(tick)
      } else {
        current = to
        setDisplay(to)
        rafId = null
      }
    }

    rafId = requestAnimationFrame(tick)
  })

  onCleanup(() => {
    if (rafId) cancelAnimationFrame(rafId)
  })

  return display
}

export function formatAnimatedNumber(value, {
  decimals = 2,
  absolute = false,
  integer = false,
  nullDisplay = '—',
} = {}) {
  if (value == null || Number.isNaN(value)) return nullDisplay

  const n = absolute ? Math.abs(value) : value
  const rounded = integer ? Math.round(n) : n

  return rounded.toLocaleString('en-IN', {
    minimumFractionDigits: integer ? 0 : decimals,
    maximumFractionDigits: integer ? 0 : decimals,
  })
}

export function animatedSign(value) {
  const n = Number(value)
  if (!Number.isFinite(n) || n === 0) return ''
  return n > 0 ? '+' : '−'
}

export function pnlTextClass(value, { zeroPositive = false } = {}) {
  const n = Number(value)
  if (!Number.isFinite(n)) return 'text-gray-400'
  if (zeroPositive && n >= 0) return 'text-emerald-400'
  if (n > 0) return 'text-emerald-400'
  if (n < 0) return 'text-rose-400'
  return 'text-gray-400'
}
