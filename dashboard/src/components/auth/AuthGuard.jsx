import { useNavigate, useLocation } from '@solidjs/router'
import { Show, onMount } from 'solid-js'
import { useAuth } from '../../stores/useAuth'

export default function AuthGuard(props) {
  const navigate = useNavigate()
  const location = useLocation()
  const auth = useAuth()

  onMount(() => {
    if (!auth.isAuthenticated()) {
      navigate(`/login?redirect=${encodeURIComponent(location.pathname)}`, { replace: true })
    }
  })

  return (
    <Show when={auth.isAuthenticated()} fallback={null}>
      {props.children}
    </Show>
  )
}
