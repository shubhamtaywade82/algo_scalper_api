/** Matches Rails `API_DASHBOARD_TOKEN` when set in production. */
export function dashboardApiHeaders() {
  const token = import.meta.env.VITE_API_DASHBOARD_TOKEN
  if (!token) return {}
  return { 'X-Api-Key': token }
}
