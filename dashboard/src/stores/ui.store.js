import { createSignal } from 'solid-js'

const [sidebarCollapsed, setSidebarCollapsed] = createSignal(false)
const [sidebarMobileOpen, setSidebarMobileOpen] = createSignal(false)
const [theme, setTheme] = createSignal('dark')
const [activeModal, setActiveModal] = createSignal(null)

export function useUIStore() {
  function toggleSidebar() {
    setSidebarCollapsed(prev => !prev)
  }

  function openModal(modalId) {
    setActiveModal(modalId)
  }

  function closeModal() {
    setActiveModal(null)
  }

  return {
    sidebarCollapsed,
    sidebarMobileOpen,
    setSidebarCollapsed,
    setSidebarMobileOpen,
    toggleSidebar,
    theme,
    setTheme,
    activeModal,
    openModal,
    closeModal,
  }
}
