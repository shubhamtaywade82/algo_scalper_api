import { createSignal, For, Show } from 'solid-js'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from './Table'
import Input from './Input'

export default function DataTable(props) {
  const [globalFilter, setGlobalFilter] = createSignal('')
  const [pageIndex, setPageIndex] = createSignal(0)
  const pageSize = () => props.pageSize || 10

  const filteredData = () => {
    const query = globalFilter().toLowerCase()
    if (!query) return props.data
    return props.data.filter(row =>
      Object.values(row).some(val =>
        String(val).toLowerCase().includes(query)
      )
    )
  }

  const totalPages = () => Math.ceil(filteredData().length / pageSize())

  const pageData = () => {
    const start = pageIndex() * pageSize()
    return filteredData().slice(start, start + pageSize())
  }

  const filteredCount = () => filteredData().length

  return (
    <div class="space-y-4">
      <Show when={props.searchable !== false}>
        <div class="flex items-center justify-between">
          <div class="relative max-w-sm">
            <Input
              placeholder="Search..."
              value={globalFilter()}
              onInput={(e) => { setGlobalFilter(e.target.value); setPageIndex(0) }}
              leftAddon={<svg class="h-4 w-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" stroke-width="2" stroke-linecap="round"/></svg>}
            />
          </div>
          <Show when={props.actions}>
            <div class="flex gap-2">{props.actions}</div>
          </Show>
        </div>
      </Show>

      <div class="border border-gray-800 rounded-lg overflow-hidden">
        <div class="overflow-auto max-h-[calc(100vh-300px)]">
          <Table>
            <TableHeader>
              <TableRow>
                <For each={props.columns}>
                  {(col) => (
                    <TableHead class={col.align === 'right' ? 'text-right' : col.align === 'center' ? 'text-center' : ''}>
                      {col.label}
                    </TableHead>
                  )}
                </For>
              </TableRow>
            </TableHeader>
            <TableBody>
              <For each={pageData()}>
                {(row) => (
                  <TableRow>
                    <For each={props.columns}>
                      {(col) => (
                        <TableCell class={col.align === 'right' ? 'text-right' : col.align === 'center' ? 'text-center' : ''}>
                          {col.render ? col.render(row) : row[col.key]}
                        </TableCell>
                      )}
                    </For>
                  </TableRow>
                )}
              </For>
              <Show when={pageData().length === 0}>
                <TableRow>
                  <TableCell colSpan={props.columns.length}>
                    <div class="flex flex-col items-center justify-center py-12 text-gray-500">
                      <p class="text-sm font-medium">No results</p>
                      <p class="text-xs mt-1">Try adjusting your search or filters</p>
                    </div>
                  </TableCell>
                </TableRow>
              </Show>
            </TableBody>
          </Table>
        </div>
      </div>

      <Show when={filteredCount() > pageSize()}>
        <div class="flex items-center justify-between px-2">
          <div class="text-sm text-gray-400">
            Showing {pageIndex() * pageSize() + 1} to {Math.min((pageIndex() + 1) * pageSize(), filteredCount())} of {filteredCount()} entries
          </div>
          <div class="flex items-center gap-2">
            <button
              onClick={() => setPageIndex(p => Math.max(0, p - 1))}
              disabled={pageIndex() === 0}
              class="px-3 py-1.5 text-xs font-medium text-gray-400 border border-gray-700 rounded hover:bg-gray-800 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            >
              Previous
            </button>
            <button
              onClick={() => setPageIndex(p => Math.min(totalPages() - 1, p + 1))}
              disabled={pageIndex() >= totalPages() - 1}
              class="px-3 py-1.5 text-xs font-medium text-gray-400 border border-gray-700 rounded hover:bg-gray-800 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            >
              Next
            </button>
          </div>
        </div>
      </Show>
    </div>
  )
}
