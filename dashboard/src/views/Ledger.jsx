import LedgerWalletPanel from '../components/LedgerWalletPanel'
import LedgerJournalPanel from '../components/LedgerJournalPanel'

export default function Ledger() {
  return (
    <div class="space-y-8">
      <div>
        <h1 class="text-lg font-black text-white uppercase tracking-widest">Paper Ledger</h1>
        <p class="text-[11px] text-gray-500 mt-1">
          Double-entry financial audit trail for paper mode — cash, deployed premium, fees, and realized PnL
        </p>
      </div>
      <LedgerWalletPanel />
      <LedgerJournalPanel />
    </div>
  )
}
