import { createSignal, createEffect } from 'solid-js'

export function useFlash(getValue) {
  const [flashClass, setFlashClass] = createSignal('')
  let prev = getValue()
  let timeout = null

  createEffect(() => {
    const newVal = getValue()
    const oldVal = prev

    if (oldVal === null || oldVal === undefined || newVal === oldVal) {
      prev = newVal
      return
    }

    if (timeout) clearTimeout(timeout)

    const direction = newVal > oldVal ? 'price-up' : 'price-down'
    setFlashClass(direction)

    timeout = setTimeout(() => {
      setFlashClass('')
      timeout = null
    }, 1000)

    prev = newVal
  })

  return flashClass
}
