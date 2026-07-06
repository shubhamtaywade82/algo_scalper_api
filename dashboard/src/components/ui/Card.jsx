const variantClasses = {
  default: 'bg-gray-900 border border-gray-800',
  elevated: 'bg-gray-900 border border-gray-800 shadow-lg',
  outlined: 'border border-gray-700 bg-transparent',
}

export function Card(props) {
  const variant = () => props.variant || 'default'
  return (
    <div class={`rounded-lg ${variantClasses[variant()]} ${props.class || ''}`}>
      {props.children}
    </div>
  )
}

export function CardHeader(props) {
  return (
    <div class={`px-4 py-3 border-b border-gray-800 ${props.class || ''}`}>
      {props.children}
    </div>
  )
}

export function CardContent(props) {
  return (
    <div class={`p-4 ${props.class || ''}`}>
      {props.children}
    </div>
  )
}

export function CardFooter(props) {
  return (
    <div class={`px-4 py-3 border-t border-gray-800 ${props.class || ''}`}>
      {props.children}
    </div>
  )
}
