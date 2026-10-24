import { Card, CardGlow } from '../ui/Card'

export default function StatCard(props) {
  const borderColor = () => props.borderColor || 'border-primary-500/50'
  const glowColor = () => props.glowColor || 'bg-primary-500/5'
  const shadowClass = () => props.shadow || 'shadow-[0_4px_20px_rgba(59,130,246,0.05)] hover:shadow-[0_8px_30px_rgba(59,130,246,0.15)]'

  return (
    <Card variant="glass" class={`${borderColor()} ${shadowClass()}`}>
      <CardGlow color={glowColor()} />
      <div class="flex flex-col relative z-10">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">
          {props.label}
        </span>
        <div class={`flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2 ${props.valueClass || ''}`}>
          {props.children}
        </div>
        <div class={`flex items-center justify-between gap-2 mt-4 ${props.footerClass || ''}`}>
          {props.footer}
        </div>
      </div>
    </Card>
  )
}
