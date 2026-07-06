import { createSignal } from 'solid-js'
import { Show } from 'solid-js'
import { useNavigate } from '@solidjs/router'
import { useAuth } from '../stores/useAuth'
import Button from '../components/ui/Button'

export default function Register() {
  const [name, setName] = createSignal('')
  const [email, setEmail] = createSignal('')
  const [password, setPassword] = createSignal('')
  const [confirm, setConfirm] = createSignal('')
  const [validationError, setValidationError] = createSignal(null)
  const auth = useAuth()
  const navigate = useNavigate()

  async function handleSubmit(e) {
    e.preventDefault()
    setValidationError(null)
    if (password() !== confirm()) {
      setValidationError('Passwords do not match')
      return
    }
    const result = await auth.register(email(), password(), name())
    if (result.ok) {
      navigate('/', { replace: true })
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
            <h1 class="text-lg font-black text-white uppercase tracking-widest">Create Account</h1>
            <p class="text-[10px] font-bold text-gray-500 uppercase tracking-widest mt-1">Register a new account</p>
          </div>

          <Show when={validationError()}>
            <div class="mb-4 px-4 py-3 rounded-xl bg-rose-500/10 border border-rose-500/20">
              <p class="text-[11px] text-rose-400 font-bold">{validationError()}</p>
            </div>
          </Show>

          <Show when={auth.error()}>
            <div class="mb-4 px-4 py-3 rounded-xl bg-rose-500/10 border border-rose-500/20">
              <p class="text-[11px] text-rose-400 font-bold">{auth.error()}</p>
            </div>
          </Show>

          <form onSubmit={handleSubmit} class="flex flex-col gap-5">
            <div class="flex flex-col gap-1.5">
              <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Name</label>
              <input
                type="text"
                value={name()}
                onInput={(e) => setName(e.target.value)}
                placeholder="Your name"
                required
                class="bg-gray-900 border border-gray-700 text-gray-200 text-sm rounded-xl px-4 py-3 focus:ring-1 focus:ring-primary-500 outline-none transition-all placeholder:text-gray-600"
              />
            </div>

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

            <div class="flex flex-col gap-1.5">
              <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Confirm Password</label>
              <input
                type="password"
                value={confirm()}
                onInput={(e) => setConfirm(e.target.value)}
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
              Create Account
            </Button>
          </form>

          <div class="mt-6 text-center">
            <a href="/login" class="text-[10px] font-bold text-gray-600 hover:text-gray-400 uppercase tracking-widest transition-colors">
              Already have an account? Sign in
            </a>
          </div>
        </div>

        <div class="mt-4 text-center">
          <p class="text-[9px] font-bold text-gray-700 uppercase tracking-widest">
            ⚠ DEPENDENCY: POST /api/auth/register not yet implemented
          </p>
        </div>
      </div>
    </div>
  )
}
