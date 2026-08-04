export function Table(props) {
  return (
    <div class="relative w-full overflow-auto">
      <table class={`w-full caption-bottom text-sm ${props.class || ''}`}>
        {props.children}
      </table>
    </div>
  )
}

export function TableHeader(props) {
  return (
    <thead class={`[&_tr]:border-b ${props.class || ''}`}>
      {props.children}
    </thead>
  )
}

export function TableBody(props) {
  return (
    <tbody class={props.class || ''}>
      {props.children}
    </tbody>
  )
}

export function TableRow(props) {
  return (
    <tr
      class={`border-b transition-colors ${props.clickable ? 'cursor-pointer hover:bg-gray-800/50' : ''} ${props.class || ''}`}
      onClick={props.onClick}
    >
      {props.children}
    </tr>
  )
}

export function TableHead(props) {
  return (
    <th class={`h-12 px-4 text-left align-middle font-medium text-gray-400 ${props.class || ''}`}>
      {props.children}
    </th>
  )
}

export function TableCell(props) {
  return (
    <td class={`p-4 align-middle ${props.class || ''}`}>
      {props.children}
    </td>
  )
}
