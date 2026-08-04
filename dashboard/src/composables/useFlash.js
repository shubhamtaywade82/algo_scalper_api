import { ref, watch } from 'vue'

export function useFlash(valueRef) {
  const flashClass = ref('')
  let timeout = null

  watch(valueRef, (newVal, oldVal) => {
    if (oldVal === null || oldVal === undefined || newVal === oldVal) return

    // Clear existing timeout
    if (timeout) clearTimeout(timeout)

    // Determine direction
    const direction = newVal > oldVal ? 'price-up' : 'price-down'

    // Set class to trigger animation (defined in style.css)
    flashClass.value = direction

    // Remove class after animation finishes (matches duration in style.css)
    timeout = setTimeout(() => {
      flashClass.value = ''
      timeout = null
    }, 1000)
  })

  return { flashClass }
}
