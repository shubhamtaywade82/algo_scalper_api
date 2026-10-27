import { createSignal } from 'solid-js'

// Start collapsed on phone-width screens so page content keeps usable width.
const [sidebarCollapsed, setSidebarCollapsed] = createSignal(typeof window !== 'undefined' && window.innerWidth < 768)
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
