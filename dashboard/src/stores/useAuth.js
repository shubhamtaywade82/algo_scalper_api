import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

const AUTH_KEY = 'algo_scalper_token'

function loadSession() {
  try {
    const raw = localStorage.getItem(AUTH_KEY)
    if (!raw) return null
    const session = JSON.parse(raw)
    if (session.expires && Date.now() > session.expires) {
      localStorage.removeItem(AUTH_KEY)
      return null
    }
    return session
  } catch {
    localStorage.removeItem(AUTH_KEY)
    return null
  }
}

function saveSession(token, user, expiresIn = 86400000) {
  const session = { token, user, expires: Date.now() + expiresIn }
  localStorage.setItem(AUTH_KEY, JSON.stringify(session))
  return session
}

export function useAuth() {
  const initial = loadSession()
  const [user, setUser] = createSignal(initial?.user || null)
  const [token, setToken] = createSignal(initial?.token || null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)
  const [backendAvailable, setBackendAvailable] = createSignal(null) // null = untested

  const isAuthenticated = () => !!token()

  async function checkBackend() {
    try {
      await apiClient.get('/auth/status')
      setBackendAvailable(true)
    } catch (e) {
      if (e.status === 404) {
        setBackendAvailable(false)
      } else {
        setBackendAvailable(true)
      }
    }
  }

  async function login(email, password) {
    setLoading(true)
    setError(null)
    try {
      const res = await apiClient.post('/auth/login', { email, password })
      const { token: t, user: u } = res.data
      setToken(t)
      setUser(u)
      saveSession(t, u)
      return { ok: true }
    } catch (e) {
      if (e.status === 404) {
        setToken('local_token')
        setUser({ name: 'Local Trader', email: email || 'local@local' })
        saveSession('local_token', { name: 'Local Trader', email: email || 'local@local' })
        return { ok: true, local: true }
      }
      setError(e.message)
      return { ok: false, error: e.message }
    } finally {
      setLoading(false)
    }
  }

  async function register(email, password, name) {
    setLoading(true)
    setError(null)
    try {
      const res = await apiClient.post('/auth/register', { email, password, name })
      const { token: t, user: u } = res.data
      setToken(t)
      setUser(u)
      saveSession(t, u)
      return { ok: true }
    } catch (e) {
      if (e.status === 404) {
        setToken('local_token')
        setUser({ name: name || 'Local Trader', email })
        saveSession('local_token', { name: name || 'Local Trader', email })
        return { ok: true, local: true }
      }
      setError(e.message)
      return { ok: false, error: e.message }
    } finally {
      setLoading(false)
    }
  }

  function logout() {
    setToken(null)
    setUser(null)
    localStorage.removeItem(AUTH_KEY)
    try {
      apiClient.delete('/auth/logout')
    } catch { /* ignore */ }
  }

  return {
    user, token, loading, error,
    isAuthenticated, backendAvailable,
    login, register, logout, checkBackend
  }
}
