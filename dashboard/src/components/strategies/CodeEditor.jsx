import { onMount, onCleanup, createEffect } from 'solid-js'
import { EditorState, Compartment } from '@codemirror/state'
import { EditorView, keymap, lineNumbers, highlightActiveLine } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands'
import { StreamLanguage } from '@codemirror/language'
import { ruby } from '@codemirror/legacy-modes/mode/ruby'
import { linter, lintGutter } from '@codemirror/lint'
import { oneDark } from '@codemirror/theme-one-dark'

export default function CodeEditor(props) {
  let containerRef
  let view

  const errorsCompartment = new Compartment()
  const readOnlyCompartment = new Compartment()

  const buildLinter = () => linter((editorView) => {
    const errors = props.errors ? props.errors() : []
    if (!errors || errors.length === 0) return []

    return errors.map((err) => {
      const line = editorView.state.doc.line(Math.min(Math.max(err.line, 1), editorView.state.doc.lines))
      return {
        from: line.from,
        to: line.to,
        severity: err.severity || 'error',
        message: err.message
      }
    })
  })

  onMount(() => {
    const state = EditorState.create({
      doc: props.code() || '',
      extensions: [
        lineNumbers(),
        lintGutter(),
        highlightActiveLine(),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
        StreamLanguage.define(ruby),
        oneDark,
        errorsCompartment.of(buildLinter()),
        readOnlyCompartment.of(EditorState.readOnly.of(!!props.readOnly)),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            props.onChange(update.state.doc.toString())
          }
        }),
        EditorView.theme({ '&': { height: '100%', fontSize: '12px' }, '.cm-scroller': { fontFamily: 'monospace' } })
      ]
    })

    view = new EditorView({ state, parent: containerRef })
  })

  onCleanup(() => view?.destroy())

  // Keep the editor in sync when `code` changes externally (e.g. loading a strategy)
  createEffect(() => {
    const next = props.code() || ''
    if (view && next !== view.state.doc.toString()) {
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: next } })
    }
  })

  // Re-run the linter whenever the errors prop changes
  createEffect(() => {
    if (!props.errors) return
    props.errors()
    view?.dispatch({ effects: errorsCompartment.reconfigure(buildLinter()) })
  })

  // Re-configure readOnly when it changes
  createEffect(() => {
    const isReadOnly = !!props.readOnly
    view?.dispatch({ effects: readOnlyCompartment.reconfigure(EditorState.readOnly.of(isReadOnly)) })
  })

  const errorCount = () => (props.errors ? props.errors().length : null)

  return (
    <div class="flex flex-col flex-1 h-full bg-[#0d1117] rounded-xl border border-white/5 overflow-hidden">
      <div ref={containerRef} class="flex-1 min-h-0 overflow-auto" />
      <div class="flex items-center justify-between px-4 py-1.5 bg-[#090d12] border-t border-white/5 text-[10px] text-gray-500 font-mono select-none">
        <div class="flex items-center gap-4">
          <span>UTF-8</span>
          <span class="text-primary-400">Ruby</span>
        </div>
        <div class="flex items-center gap-1.5">
          {errorCount() === null ? (
            <span class="text-gray-500 font-black">Not validated yet</span>
          ) : errorCount() === 0 ? (
            <>
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-400" />
              <span class="text-emerald-500 font-black">No errors</span>
            </>
          ) : (
            <>
              <span class="w-1.5 h-1.5 rounded-full bg-rose-400" />
              <span class="text-rose-400 font-black">{errorCount()} error{errorCount() === 1 ? '' : 's'}</span>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
