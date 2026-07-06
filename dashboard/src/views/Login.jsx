import { createSignal, Show } from 'solid-js'
import { useNavigate, useSearchParams } from '@solidjs/router'
import { useAuth } from '../stores/useAuth'
import Button from '../components/ui/Button'

export default function Login() {
  const [email, setEmail] = createSignal('')
  const [password, setPassword] = createSignal('')
  const [localMode, setLocalMode] = createSignal(false)
  const auth = useAuth()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()

  async function handleSubmit(e) {
    e.preventDefault()
    const result = await auth.login(email(), password())
    if (result.ok) {
      if (result.local) setLocalMode(true)
      const redirect = searchParams.redirect || '/'
      navigate(redirect, { replace: true })
    }
  }

  return (
    <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-gray-950 via-gray-900 to-gray-950">
      <div class="w-full max-w-md px-6">
        <div class="glass rounded-3xl p-8 border border-white/5 shadow-2xl">
          <div class="flex flex-col items-center mb-8">
            <div class="w-12 h-12 rounded-full bg-primary-500/20 flex items-center justify-center mb-4">
              <span class="text-2xl font-black text-primary-400">A</span>
            </div>
            <h1 class="text-lg font-black text-white uppercase tracking-widest">Algo Scalper</h1>
            <p class="text-[10px] font-bold text-gray-500 uppercase tracking-widest mt-1">Sign in to your account</p>
          </div>

          <Show when={auth.error()}>
            <div class="mb-4 px-4 py-3 rounded-xl bg-rose-500/10 border border-rose-500/20">
              <p class="text-[11px] text-rose-400 font-bold">{auth.error()}</p>
            </div>
          </Show>

          <form onSubmit={handleSubmit} class="flex flex-col gap-5">
            <div class="flex flex-col gap-1.5">
              <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Email</label>
              <input
                type="email"
                value={email()}
                onInput={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                required
                class="bg-gray-900 border border-gray-700 text-gray-200 text-sm rounded-xl px-4 py-3 focus:ring-1 focus:ring-primary-500 outline-none transition-all placeholder:text-gray-600"
              />
            </div>

            <div class="flex flex-col gap-1.5">
              <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Password</label>
              <input
                type="password"
                value={password()}
                onInput={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                class="bg-gray-900 border border-gray-700 text-gray-200 text-sm rounded-xl px-4 py-3 focus:ring-1 focus:ring-primary-500 outline-none transition-all placeholder:text-gray-600"
              />
            </div>

            <Button
              type="submit"
              variant="default"
              class="!bg-primary-600 hover:!bg-primary-500 text-sm font-black uppercase tracking-widest rounded-xl py-3 h-auto"
              loading={auth.loading()}
            >
              Sign In
            </Button>
          </form>

          <div class="mt-6 text-center">
            <a href="/register" class="text-[10px] font-bold text-gray-600 hover:text-gray-400 uppercase tracking-widest transition-colors">
              Don't have an account? Register
            </a>
          </div>
        </div>

        <Show when={!localMode()}>
          <div class="mt-4 text-center">
            <p class="text-[9px] font-bold text-gray-700 uppercase tracking-widest">
              Auth backend unavailable — signing in enters local mode
            </p>
          </div>
        </Show>
        <Show when={localMode()}>
          <div class="mt-4 text-center">
            <p class="text-[9px] font-bold text-emerald-600 uppercase tracking-widest">
              ✓ Entering local mode — auth endpoints not required
            </p>
          </div>
        </Show>
      </div>
    </div>
  )
}
