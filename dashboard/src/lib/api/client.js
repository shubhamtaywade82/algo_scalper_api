import axios from 'axios'

const client = axios.create({
  baseURL: '/api',
  timeout: 30000,
  headers: { 'Content-Type': 'application/json' }
})

client.interceptors.request.use(config => {
  const token = import.meta.env.VITE_API_DASHBOARD_TOKEN
  if (token) {
    config.headers['X-Api-Key'] = token
  }
  return config
})

client.interceptors.response.use(
  response => response,
  error => {
    const status = error.response?.status
    const data = error.response?.data

    if (status === 401 || status === 403) {
      const event = new CustomEvent('api:auth-error', { detail: { status, data } })
      window.dispatchEvent(event)
    }

    if (status === 429) {
      const event = new CustomEvent('api:rate-limited', { detail: { status, data } })
      window.dispatchEvent(event)
    }

    const message = data?.error || data?.message || error.message || 'Unknown error'
    const apiError = new Error(message)
    apiError.status = status
    apiError.data = data
    apiError.originalError = error
    return Promise.reject(apiError)
  }
)

export default client
