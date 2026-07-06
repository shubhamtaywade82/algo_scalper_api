import { createSignal, createEffect, onMount, createMemo } from 'solid-js'

export default function CodeEditor(props) {
  let textareaRef
  let gutterRef

  const [cursorLine, setCursorLine] = createSignal(1)
  const [cursorCol, setCursorCol] = createSignal(1)

  const lineCount = createMemo(() => {
    const text = props.code() || ''
    return text.split('\n').length
  })

  // Synchronize scrolling of gutter and textarea
  const handleScroll = () => {
    if (textareaRef && gutterRef) {
      gutterRef.scrollTop = textareaRef.scrollTop
    }
  }

  // Update cursor position line and column
  const handleCursorMove = (e) => {
    const el = e.target
    const textBeforeCursor = el.value.substring(0, el.selectionStart)
    const lines = textBeforeCursor.split('\n')
    setCursorLine(lines.length)
    setCursorCol(lines[lines.length - 1].length + 1)
  }

  // Handle Tab key press to insert spaces
  const handleKeyDown = (e) => {
    if (e.key === 'Tab') {
      e.preventDefault()
      const el = e.target
      const start = el.selectionStart
      const end = el.selectionEnd
      const text = el.value
      const value = text.substring(0, start) + '  ' + text.substring(end)
      props.onChange(value)
      
      // Reset cursor position
      setTimeout(() => {
        el.selectionStart = el.selectionEnd = start + 2
      }, 0)
    }
  }

  return (
    <div class="flex flex-col flex-1 h-full bg-[#0d1117] rounded-xl border border-white/5 overflow-hidden">
      {/* Editor Body */}
      <div class="flex flex-1 relative min-h-0">
        {/* Line Numbers Gutter */}
        <div
          ref={gutterRef}
          class="w-12 bg-[#090d12] text-gray-600 font-mono text-[11px] text-right pr-2 py-4 select-none overflow-hidden border-r border-white/5"
          style="line-height: 18px;"
        >
          {Array.from({ length: lineCount() }).map((_, i) => (
            <div class={cursorLine() === i + 1 ? 'text-gray-400 font-bold bg-white/5' : ''}>{i + 1}</div>
          ))}
        </div>

        {/* Textarea */}
        <textarea
          ref={textareaRef}
          value={props.code() || ''}
          onInput={(e) => props.onChange(e.target.value)}
          onScroll={handleScroll}
          onKeyUp={handleCursorMove}
          onClick={handleCursorMove}
          onKeyDown={handleKeyDown}
          readOnly={props.readOnly}
          class="flex-1 bg-[#0d1117] text-gray-200 font-mono text-[12px] p-4 resize-none outline-none border-none focus:ring-0 leading-[18px] overflow-auto h-full"
          placeholder="# Write strategy logic here..."
          spellcheck={false}
        />
      </div>

      {/* Editor Status Bar */}
      <div class="flex items-center justify-between px-4 py-1.5 bg-[#090d12] border-t border-white/5 text-[10px] text-gray-500 font-mono select-none">
        <div class="flex items-center gap-4">
          <span>Line {cursorLine()}, Col {cursorCol()}</span>
          <span>Spaces: 2</span>
          <span>UTF-8</span>
          <span class="text-primary-400">Ruby</span>
        </div>
        <div class="flex items-center gap-1.5">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-400" />
          <span class="text-emerald-500 font-black">No errors</span>
        </div>
      </div>
    </div>
  )
}
