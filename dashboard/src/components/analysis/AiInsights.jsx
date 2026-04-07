import { createMemo } from 'solid-js'
import { Show } from 'solid-js'

function formatMarkdown(raw) {
  if (!raw) return ''
  return raw
    .replace(/\*\*(.*?)\*\*/g, '<strong class="text-white">$1</strong>')
    .replace(/#{1,3}\s(.*?)(\n|$)/g, '<div class="text-cyan-400 font-black text-xs tracking-wider mt-3 mb-1">$1</div>')
    .replace(/\n/g, '<br>')
}

export default function AiInsights(props) {
  const displayText = createMemo(() =>
    props.snapshotData ?? (
      typeof props.analysis === 'string' ? props.analysis :
      props.analysis ? JSON.stringify(props.analysis, null, 2) : null
    )
  )

  const isLiveSnapshot = createMemo(() => props.snapshotData !== null && props.snapshotData !== undefined)

  return (
    <div class="glass rounded-2xl p-6 glass-hover">
      <div class="flex items-center justify-between gap-3 mb-5">
        <div class="flex items-center gap-3">
          <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">🤖 AI Analysis</span>
          <Show when={isLiveSnapshot()}>
            <span class="text-[9px] font-bold text-emerald-400 bg-emerald-400/10 px-2 py-0.5 rounded uppercase tracking-wider">
              🔴 Live snapshot
            </span>
          </Show>
          <Show when={!isLiveSnapshot() && displayText()}>
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
          </Show>
        </div>

        <Show when={props.onSnapshot}>
          <button
            onClick={() => props.onSnapshot()}
            disabled={props.snapshotLoading}
            class="px-3 py-1.5 rounded-lg text-[9px] font-black uppercase tracking-widest glass border border-white/10 text-gray-400 hover:text-cyan-300 hover:border-cyan-500/30 transition-all duration-300 disabled:opacity-40 flex items-center gap-1.5"
          >
            <Show when={props.snapshotLoading}>
              <span class="w-3 h-3 border border-gray-400 border-t-transparent rounded-full animate-spin"></span>
            </Show>
            <span>{props.snapshotLoading ? 'Fetching...' : '🤖 Snapshot'}</span>
          </button>
        </Show>
      </div>

      <Show when={props.snapshotError}>
        <div class="text-rose-400 text-[10px] font-bold mb-3 px-2 py-1 bg-rose-500/10 rounded">
          ⚠ {props.snapshotError}
        </div>
      </Show>

      <div class="relative">
        <Show when={displayText()}>
          <div
            class={`text-xs leading-relaxed text-gray-400 max-h-[500px] overflow-y-auto pr-2 ${props.snapshotLoading ? 'opacity-30' : ''}`}
            innerHTML={formatMarkdown(displayText())}
          ></div>
        </Show>

        <Show when={!displayText() && !props.snapshotLoading}>
          <div class="text-center py-10">
            <div class="text-gray-600 text-[10px] font-bold tracking-widest uppercase">AI insights unavailable</div>
            <div class="text-gray-700 text-[9px] mt-2 tracking-wider">The AI model is either processing data or timed out. Please wait or check model performance.</div>
          </div>
        </Show>

        <Show when={props.snapshotLoading && !displayText()}>
          <div class="flex items-center justify-center py-10">
            <div class="w-5 h-5 border border-white/10 border-t-cyan-400 rounded-full animate-spin mr-3"></div>
            <span class="text-[10px] text-gray-500 font-bold tracking-widest uppercase">Generating snapshot...</span>
          </div>
        </Show>
      </div>
    </div>
  )
}
