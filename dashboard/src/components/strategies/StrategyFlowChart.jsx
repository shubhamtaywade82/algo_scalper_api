import { createSignal } from 'solid-js'

export default function StrategyFlowChart(props) {
  const [zoom, setZoom] = createSignal(100)

  const handleZoomIn = () => setZoom(prev => Math.min(150, prev + 10))
  const handleZoomOut = () => setZoom(prev => Math.max(50, prev - 10))
  const handleReset = () => setZoom(100)

  return (
    <div class="glass border border-white/5 rounded-2xl overflow-hidden flex flex-col h-full bg-[#0d1117]/30">
      {/* Title / Controls */}
      <div class="flex items-center justify-between px-4 py-2.5 border-b border-white/5 bg-white/[0.01]">
        <h4 class="text-[9px] font-black text-gray-400 uppercase tracking-widest flex items-center gap-1.5">
          <span class="w-1.5 h-1.5 rounded-full bg-violet-400" />
          Logic Flow (Visual)
        </h4>
        <div class="flex items-center gap-2">
          <button
            onClick={handleZoomOut}
            class="w-5 h-5 flex items-center justify-center text-xs font-black text-gray-500 hover:text-white bg-white/5 rounded hover:bg-white/10"
          >
            -
          </button>
          <span class="text-[9px] font-mono text-gray-500 w-8 text-center">{zoom()}%</span>
          <button
            onClick={handleZoomIn}
            class="w-5 h-5 flex items-center justify-center text-xs font-black text-gray-500 hover:text-white bg-white/5 rounded hover:bg-white/10"
          >
            +
          </button>
          <button
            onClick={handleReset}
            class="px-1.5 py-0.5 text-[8px] font-black text-gray-500 hover:text-white bg-white/5 rounded hover:bg-white/10 uppercase tracking-wider"
          >
            Reset
          </button>
        </div>
      </div>

      {/* SVG Canvas */}
      <div class="flex-1 flex items-center justify-center p-4 min-h-0 overflow-auto">
        <div
          style={{
            transform: `scale(${zoom() / 100})`,
            'transform-origin': 'center center',
            transition: 'transform 0.1s ease-out'
          }}
          class="w-full max-w-[320px] aspect-[4/3] flex items-center justify-center"
        >
          <svg viewBox="0 0 320 240" class="w-full h-full">
            <defs>
              <linearGradient id="gradientGreen" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#10b981" stop-opacity="0.2" />
                <stop offset="100%" stop-color="#059669" stop-opacity="0.1" />
              </linearGradient>
              <linearGradient id="gradientRed" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#f43f5e" stop-opacity="0.2" />
                <stop offset="100%" stop-color="#e11d48" stop-opacity="0.1" />
              </linearGradient>
              <linearGradient id="gradientBlue" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#3b82f6" stop-opacity="0.2" />
                <stop offset="100%" stop-color="#2563eb" stop-opacity="0.1" />
              </linearGradient>
            </defs>

            {/* Start Node: Market Open */}
            <rect x="110" y="10" width="100" height="30" rx="15" fill="rgba(255,255,255,0.02)" stroke="rgba(255,255,255,0.1)" stroke-width="1" />
            <text x="160" y="28" fill="#9ca3af" font-size="9" text-anchor="middle" font-family="monospace" font-weight="bold">Market Open</text>

            {/* Connection: Start -> Action */}
            <line x1="160" y1="40" x2="160" y2="60" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />

            {/* Action Node: Record Opening Range */}
            <rect x="90" y="60" width="140" height="36" rx="6" fill="url(#gradientBlue)" stroke="#3b82f6" stroke-opacity="0.4" stroke-width="1" />
            <text x="160" y="78" fill="#60a5fa" font-size="9" text-anchor="middle" font-family="monospace" font-weight="bold">Record Range</text>
            <text x="160" y="90" fill="#9ca3af" font-size="8" text-anchor="middle" font-family="monospace">(15-min High/Low)</text>

            {/* Connection: Action -> Decision */}
            <line x1="160" y1="96" x2="160" y2="120" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" />

            {/* Decision Node: Breakout? */}
            <polygon points="160,120 210,145 160,170 110,145" fill="rgba(255,255,255,0.01)" stroke="#f59e0b" stroke-opacity="0.5" stroke-width="1" />
            <text x="160" y="148" fill="#fbbf24" font-size="9" text-anchor="middle" font-family="monospace" font-weight="bold">Breakout?</text>

            {/* Connection: Decision -> Buy Call (Yes Up) */}
            <path d="M 210,145 L 260,145 L 260,190" fill="none" stroke="#10b981" stroke-opacity="0.4" stroke-dasharray="2,2" stroke-width="1.5" />
            <text x="240" y="138" fill="#10b981" font-size="8" font-family="monospace">Yes (Up)</text>

            {/* Connection: Decision -> Buy Put (Yes Down) */}
            <path d="M 110,145 L 60,145 L 60,190" fill="none" stroke="#f43f5e" stroke-opacity="0.4" stroke-dasharray="2,2" stroke-width="1.5" />
            <text x="80" y="138" fill="#f43f5e" font-size="8" font-family="monospace">Yes (Down)</text>

            {/* Connection: Decision -> Wait (No Loop) */}
            <path d="M 160,170 L 160,185 L 305,185 L 305,78 L 230,78" fill="none" stroke="rgba(255,255,255,0.1)" stroke-width="1" />
            <text x="280" y="180" fill="#6b7280" font-size="8" font-family="monospace">No</text>

            {/* Target 1: Buy Call */}
            <rect x="210" y="190" width="100" height="36" rx="6" fill="url(#gradientGreen)" stroke="#10b981" stroke-opacity="0.5" stroke-width="1" />
            <text x="260" y="212" fill="#34d399" font-size="9" text-anchor="middle" font-family="monospace" font-weight="bold">Buy Call (CE)</text>

            {/* Target 2: Buy Put */}
            <rect x="10" y="190" width="100" height="36" rx="6" fill="url(#gradientRed)" stroke="#f43f5e" stroke-opacity="0.5" stroke-width="1" />
            <text x="60" y="212" fill="#f87171" font-size="9" text-anchor="middle" font-family="monospace" font-weight="bold">Buy Put (PE)</text>
          </svg>
        </div>
      </div>
    </div>
  )
}
