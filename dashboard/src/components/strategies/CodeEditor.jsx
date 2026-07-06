import { createSignal, createMemo, For, onMount } from 'solid-js'

export default function CodeEditor(props) {
  let textareaRef
  let gutterRef
  const [cursorLine, setCursorLine] = createSignal(1)
  const [cursorCol, setCursorCol] = createSignal(1)

  const lineCount = createMemo(() => {
    const text = props.code()
    if (!text) return 1
    return text.split('\n').length
  })

  const lines = createMemo(() => Array.from({ length: lineCount() }, (_, i) => i + 1))

  function updateCursorPosition() {
    if (!textareaRef) return
    const val = textareaRef.value
    const pos = textareaRef.selectionStart
    const before = val.substring(0, pos)
    const lineNum = before.split('\n').length
    const lastNewline = before.lastIndexOf('\n')
    const col = pos - lastNewline
    setCursorLine(lineNum)
    setCursorCol(col)
  }

  function handleScroll() {
    if (gutterRef && textareaRef) {
      gutterRef.scrollTop = textareaRef.scrollTop
    }
  }

  function handleInput(e) {
    if (props.onChange) {
      props.onChange(e.target.value)
    }
    updateCursorPosition()
  }

  onMount(() => {
    if (textareaRef) {
      textareaRef.addEventListener('click', updateCursorPosition)
      textareaRef.addEventListener('keyup', updateCursorPosition)
    }
  })

  return (
    <div class="flex flex-col h-full rounded-xl overflow-hidden border border-white/10">
      {/* Editor area */}
      <div class="flex flex-1 overflow-hidden" style="background: #0d1117">
        {/* Line numbers gutter */}
        <div
          ref={gutterRef}
          class="select-none overflow-hidden flex-shrink-0"
          style={{
            'background': '#0d1117',
            'border-right': '1px solid rgba(255,255,255,0.06)',
            'padding': '12px 0',
            'min-width': '52px',
            'text-align': 'right',
          }}
        >
          <For each={lines()}>
            {(num) => (
              <div
                class="font-mono text-[12px] leading-[20px] px-3"
                style={{
                  color: num === cursorLine() ? 'rgba(255,255,255,0.6)' : 'rgba(255,255,255,0.2)',
                }}
              >
                {num}
              </div>
            )}
          </For>
        </div>

        {/* Textarea */}
        <textarea
          ref={textareaRef}
          value={props.code()}
          onInput={handleInput}
          onScroll={handleScroll}
          readOnly={props.readOnly || false}
          spellcheck={false}
          class="flex-1 bg-transparent text-gray-300 font-mono text-[12px] leading-[20px] p-3 outline-none resize-none overflow-auto"
          style={{
            'tab-size': '2',
            'caret-color': '#58a6ff',
            'white-space': 'pre',
            'word-wrap': 'normal',
            'overflow-wrap': 'normal',
          }}
        />
      </div>

      {/* Status bar */}
      <div
        class="flex items-center justify-between px-4 py-1.5 text-[11px] font-mono border-t border-white/5 flex-shrink-0"
        style="background: #161b22; color: rgba(255,255,255,0.4)"
      >
        <div class="flex items-center gap-4">
          <span>Ln {cursorLine()}, Col {cursorCol()}</span>
          <span>Spaces: 2</span>
          <span>UTF-8</span>
        </div>
        <div class="flex items-center gap-4">
          <span class="capitalize">{props.language || 'Ruby'}</span>
          <span class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-emerald-500 inline-block" />
            0 errors
          </span>
        </div>
      </div>
    </div>
  )
}
