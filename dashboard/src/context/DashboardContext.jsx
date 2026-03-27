import { createContext, useContext } from 'solid-js'

export const DashboardContext = createContext()

export function useDashboardContext() {
  return useContext(DashboardContext)
}
