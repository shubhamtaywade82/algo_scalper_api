import { createSignal, createResource, For, Show } from 'solid-js'
import { apiClient } from '../lib/api'
import Badge from '../components/ui/Badge'

// Local LLMs take a few seconds per tool round; the default 30s client timeout is too tight.
const ASK_TIMEOUT_MS = 120000
const INDEX_CHOICES = ['', 'NIFTY', 'BANKNIFTY', 'SENSEX']
const QUICK_QUESTIONS = [
  'Is NIFTY tradeable right now?',
  'Is the circuit breaker tripped and how much daily loss is used?',
  'Is the trading system healthy? Anything stale?',
  'Compare NIFTY, BANKNIFTY and SENSEX right now.',
]

const errorMessage = (e) => e.response?.data?.error || e.message

async function fetchStatus() {
  const res = await apiClient.get('/mcp/tools')
  return res.data
}

// Renders **bold** without innerHTML: answers come from an LLM and must stay plain text.
function PlainMarkdown(props) {
  const parts = () => String(props.text || '').split(/\*\*(.+?)\*\*/g)
  return (
    <p class="text-sm text-gray-200 whitespace-pre-wrap leading-relaxed">
      <For each={parts()}>{(part, i) => (i() % 2 ? <strong class="text-white">{part}</strong> : part)}</For>
    </p>
  )
}

function StatusBar(props) {
  return (
    <div class="glass rounded-2xl p-5 flex flex-wrap items-center gap-x-8 gap-y-3">
      <div class="flex items-center gap-3">
        <span class={`w-2.5 h-2.5 rounded-full ${props.status?.online ? 'bg-emerald-400 animate-pulse' : 'bg-rose-500'}`} />
        <span class="text-xs font-black uppercase tracking-widest text-white">
          MCP server {props.status?.online ? 'online' : 'offline'}
        </span>
      </div>
      <Stat label="Endpoint" value={props.status?.url} />
      <Stat label="Local model" value={props.status?.model} />
      <Stat label="Tools" value={props.status?.tools?.length ?? 0} />
      <Stat label="Access" value="Read-only · no orders" />
      <button type="button" class="ml-auto text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider" onClick={props.onRefresh}>
        ↻ Refresh
      </button>
      <Show when={props.status && !props.status.online}>
        <p class="w-full text-[11px] text-rose-400">
          {props.status.error} — start it with <code class="text-rose-300">./bin/dev</code> (process "mcp").
        </p>
      </Show>
    </div>
  )
}

function Stat(props) {
  return (
    <div>
      <div class="text-[9px] font-black text-gray-500 uppercase tracking-widest">{props.label}</div>
      <div class="text-xs font-bold text-gray-200 text-data">{props.value ?? '—'}</div>
    </div>
  )
}

function ToolCard(props) {
  const [index, setIndex] = createSignal('')
  const [result, setResult] = createSignal(null)
  const [running, setRunning] = createSignal(false)
  const takesIndex = () => Boolean(props.tool.inputSchema?.properties?.index)

  async function run() {
    setRunning(true)
    try {
      const args = takesIndex() && index() ? { index: index() } : {}
      const res = await apiClient.post(`/mcp/tools/${props.tool.name}/calls`, { arguments: args })
      setResult(JSON.stringify(res.data.result, null, 2))
    } catch (e) {
      setResult(`Error: ${errorMessage(e)}`)
    } finally {
      setRunning(false)
    }
  }

  return (
    <div class="glass rounded-2xl p-5 space-y-3">
      <div class="flex items-center justify-between gap-3">
        <code class="text-xs font-black text-primary-400">{props.tool.name}</code>
        <div class="flex items-center gap-2">
          <Show when={takesIndex()}>
            <select class="bg-white/5 border border-white/10 rounded-lg text-[11px] text-gray-200 px-2 py-1" value={index()} onChange={(e) => setIndex(e.currentTarget.value)}>
              <For each={INDEX_CHOICES}>{(c) => <option value={c}>{c || 'All indices'}</option>}</For>
            </select>
          </Show>
          <button type="button" disabled={running()} onClick={run}
            class="px-3 py-1 rounded-lg bg-primary-600 hover:bg-primary-500 disabled:opacity-50 text-[10px] font-black uppercase tracking-wider text-white">
            {running() ? 'Running…' : 'Run'}
          </button>
        </div>
      </div>
      <p class="text-[11px] text-gray-400 leading-relaxed">{props.tool.description}</p>
      <Show when={result()}>
        <pre class="max-h-72 overflow-auto rounded-xl bg-black/40 p-3 text-[10px] text-gray-300 text-data">{result()}</pre>
      </Show>
    </div>
  )
}

function AskPanel(props) {
  const [question, setQuestion] = createSignal('')
  const [history, setHistory] = createSignal([])
  const [asking, setAsking] = createSignal(false)

  async function ask(text) {
    const q = (text ?? question()).trim()
    if (!q || asking()) return
    setAsking(true)
    setQuestion('')
    try {
      const res = await apiClient.post('/mcp/questions', { question: q }, { timeout: ASK_TIMEOUT_MS })
      setHistory([{ question: q, ...res.data }, ...history()])
    } catch (e) {
      setHistory([{ question: q, error: errorMessage(e) }, ...history()])
    } finally {
      setAsking(false)
    }
  }

  return (
    <div class="glass rounded-2xl p-5 space-y-4">
      <div class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Ask the local model</div>
      <form class="flex gap-2" onSubmit={(e) => { e.preventDefault(); ask() }}>
        <input value={question()} onInput={(e) => setQuestion(e.currentTarget.value)} maxLength={500}
          placeholder="e.g. Why is there no trade setup right now?" disabled={props.disabled || asking()}
          class="flex-1 bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-gray-100 placeholder-gray-600 focus:outline-none focus:border-primary-500/50" />
        <button type="submit" disabled={props.disabled || asking() || !question().trim()}
          class="px-5 rounded-xl bg-primary-600 hover:bg-primary-500 disabled:opacity-50 text-xs font-black uppercase tracking-wider text-white">
          {asking() ? 'Thinking…' : 'Ask'}
        </button>
      </form>
      <div class="flex flex-wrap gap-2">
        <For each={QUICK_QUESTIONS}>
          {(q) => (
            <button type="button" disabled={props.disabled || asking()} onClick={() => ask(q)}
              class="px-3 py-1.5 rounded-full bg-white/5 hover:bg-white/10 disabled:opacity-50 text-[11px] text-gray-300">{q}</button>
          )}
        </For>
      </div>
      <div class="space-y-3">
        <For each={history()}>{(entry) => <AnswerCard entry={entry} />}</For>
      </div>
    </div>
  )
}

function AnswerCard(props) {
  const e = () => props.entry
  return (
    <div class="rounded-xl border border-white/5 bg-white/[0.02] p-4 space-y-2">
      <div class="text-xs font-bold text-primary-300">{e().question}</div>
      <Show when={!e().error} fallback={<p class="text-xs text-rose-400">{e().error}</p>}>
        <PlainMarkdown text={e().answer} />
        <div class="flex flex-wrap items-center gap-2 pt-1">
          <For each={e().tools_used}>{(t) => <Badge variant="info" class="text-[9px]">{t}</Badge>}</For>
          <Show when={!e().tools_used?.length}>
            <Badge variant="warning" class="text-[9px]">no tool called — answer not grounded in live data</Badge>
          </Show>
          <span class="text-[10px] text-gray-500 ml-auto">{e().model} · {(e().duration_ms / 1000).toFixed(1)}s</span>
        </div>
      </Show>
    </div>
  )
}

export default function AiAssistant() {
  const [status, { refetch }] = createResource(fetchStatus)

  return (
    <div class="space-y-6">
      <StatusBar status={status()} onRefresh={refetch} />
      <p class="text-[11px] text-gray-500">
        Answers come from a small local model ({status()?.model || 'Ollama'}) reading live data through the MCP tools.
        It explains; it cannot trade. Always check the numbers against the dashboard.
      </p>
      <AskPanel disabled={!status()?.online} />
      <div>
        <div class="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-3">MCP tools (same ones Cursor / Claude Code see)</div>
        <div class="grid gap-4 lg:grid-cols-3">
          <For each={status()?.tools || []}>{(tool) => <ToolCard tool={tool} />}</For>
        </div>
      </div>
    </div>
  )
}
