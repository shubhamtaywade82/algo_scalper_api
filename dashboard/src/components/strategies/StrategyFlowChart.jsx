import { createSignal } from 'solid-js'

export default function StrategyFlowChart(props) {
  const [zoom, setZoom] = createSignal(100)

  function zoomIn() {
    setZoom(prev => Math.min(prev + 10, 200))
  }

  function zoomOut() {
    setZoom(prev => Math.max(prev - 10, 40))
  }

  function resetZoom() {
    setZoom(100)
  }

  return (
    <div class="relative h-full flex flex-col">
      {/* SVG Canvas */}
      <div class="flex-1 overflow-auto flex items-center justify-center" style="min-height: 0">
        <svg
          viewBox="0 0 500 420"
          class="w-full h-full"
          style={{ 'max-height': '100%', 'max-width': '100%' }}
        >
          <g transform={`scale(${zoom() / 100})`} transform-origin="250 210">
            {/* ── Start Node: Market Open ── */}
            <rect x="175" y="20" width="150" height="44" rx="22" ry="22"
              fill="rgba(59,130,246,0.08)" stroke="rgba(59,130,246,0.5)" stroke-width="1.5" />
            <text x="250" y="47" text-anchor="middle" fill="white" font-size="12" font-weight="700"
              font-family="Inter, system-ui, sans-serif">
              Market Open
            </text>

            {/* Arrow: Start → Decision */}
            <line x1="250" y1="64" x2="250" y2="110" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <polygon points="250,116 246,108 254,108" fill="rgba(255,255,255,0.25)" />

            {/* ── Decision Diamond: Condition Met? ── */}
            <g transform="translate(250, 155)">
              <rect x="-55" y="-40" width="110" height="80" rx="6" ry="6"
                transform="rotate(45)" fill="rgba(245,158,11,0.06)" stroke="rgba(245,158,11,0.5)" stroke-width="1.5"
                style={{ 'transform-origin': '0 0', 'transform-box': 'fill-box' }} />
              {/* Overlay a cleaner diamond with path */}
              <path d="M 0,-55 L 70,0 L 0,55 L -70,0 Z"
                fill="rgba(245,158,11,0.06)" stroke="rgba(245,158,11,0.5)" stroke-width="1.5" />
              <text x="0" y="-4" text-anchor="middle" fill="white" font-size="11" font-weight="700"
                font-family="Inter, system-ui, sans-serif">
                Condition
              </text>
              <text x="0" y="12" text-anchor="middle" fill="white" font-size="11" font-weight="700"
                font-family="Inter, system-ui, sans-serif">
                Met?
              </text>
            </g>

            {/* Arrow: Decision → Yes (right) */}
            <line x1="320" y1="155" x2="370" y2="155" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <line x1="370" y1="155" x2="370" y2="248" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <polygon points="370,254 366,246 374,246" fill="rgba(16,185,129,0.6)" />
            <text x="340" y="145" text-anchor="middle" fill="rgba(16,185,129,0.8)" font-size="10" font-weight="700"
              font-family="Inter, system-ui, sans-serif">
              Yes
            </text>

            {/* Arrow: Decision → No (left) */}
            <line x1="180" y1="155" x2="130" y2="155" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <line x1="130" y1="155" x2="130" y2="248" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <polygon points="130,254 126,246 134,246" fill="rgba(244,63,94,0.6)" />
            <text x="160" y="145" text-anchor="middle" fill="rgba(244,63,94,0.8)" font-size="10" font-weight="700"
              font-family="Inter, system-ui, sans-serif">
              No
            </text>

            {/* ── Yes Action: Buy Call (right side) ── */}
            <rect x="310" y="258" width="120" height="40" rx="10" ry="10"
              fill="rgba(16,185,129,0.08)" stroke="rgba(16,185,129,0.5)" stroke-width="1.5" />
            <text x="370" y="283" text-anchor="middle" fill="rgba(16,185,129,0.9)" font-size="12" font-weight="700"
              font-family="Inter, system-ui, sans-serif">
              Buy Call
            </text>

            {/* ── No Action: Buy Put / Wait (left side) ── */}
            <rect x="70" y="258" width="120" height="40" rx="10" ry="10"
              fill="rgba(244,63,94,0.08)" stroke="rgba(244,63,94,0.5)" stroke-width="1.5" />
            <text x="130" y="283" text-anchor="middle" fill="rgba(244,63,94,0.9)" font-size="12" font-weight="700"
              font-family="Inter, system-ui, sans-serif">
              Buy Put / Wait
            </text>

            {/* Arrows to End node */}
            <line x1="370" y1="298" x2="370" y2="330" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <line x1="370" y1="330" x2="250" y2="330" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <line x1="130" y1="298" x2="130" y2="330" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <line x1="130" y1="330" x2="250" y2="330" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <line x1="250" y1="330" x2="250" y2="350" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />
            <polygon points="250,356 246,348 254,348" fill="rgba(255,255,255,0.25)" />

            {/* ── End Node: Position Managed ── */}
            <rect x="175" y="360" width="150" height="40" rx="20" ry="20"
              fill="rgba(139,92,246,0.08)" stroke="rgba(139,92,246,0.4)" stroke-width="1.5" />
            <text x="250" y="385" text-anchor="middle" fill="rgba(139,92,246,0.9)" font-size="11" font-weight="700"
              font-family="Inter, system-ui, sans-serif">
              Position Managed
            </text>

            {/* Strategy name label */}
            <text x="250" y="415" text-anchor="middle" fill="rgba(255,255,255,0.15)" font-size="9" font-weight="600"
              font-family="Inter, system-ui, sans-serif">
              {props.strategyName || 'Strategy Flow'}
            </text>
          </g>
        </svg>
      </div>

      {/* Zoom Controls */}
      <div class="absolute bottom-3 right-3 flex items-center gap-1.5 bg-black/40 backdrop-blur-sm rounded-lg px-2 py-1 border border-white/10">
        <button
          onClick={zoomOut}
          class="w-6 h-6 flex items-center justify-center rounded text-gray-400 hover:text-white hover:bg-white/10 transition text-sm font-bold"
        >
          −
        </button>
        <button
          onClick={resetZoom}
          class="px-2 py-0.5 text-[10px] font-mono text-gray-400 hover:text-white transition min-w-[40px] text-center"
        >
          {zoom()}%
        </button>
        <button
          onClick={zoomIn}
          class="w-6 h-6 flex items-center justify-center rounded text-gray-400 hover:text-white hover:bg-white/10 transition text-sm font-bold"
        >
          +
        </button>
        <div class="w-px h-4 bg-white/10 mx-0.5" />
        <button
          class="w-6 h-6 flex items-center justify-center rounded text-gray-400 hover:text-white hover:bg-white/10 transition"
          title="Fullscreen"
        >
          <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
            <path d="M3 4a1 1 0 011-1h4a1 1 0 010 2H5v3a1 1 0 01-2 0V4zM16 4a1 1 0 00-1-1h-4a1 1 0 000 2h3v3a1 1 0 002 0V4zM3 16a1 1 0 001 1h4a1 1 0 000-2H5v-3a1 1 0 00-2 0v4zM16 16a1 1 0 01-1 1h-4a1 1 0 010-2h3v-3a1 1 0 012 0v4z" />
          </svg>
        </button>
      </div>
    </div>
  )
}
