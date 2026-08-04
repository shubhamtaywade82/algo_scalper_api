import LedgerWalletPanel from '../components/LedgerWalletPanel'
import LedgerJournalPanel from '../components/LedgerJournalPanel'

export default function Ledger() {
  return (
    <div class="space-y-8">

      <LedgerWalletPanel />
      <LedgerJournalPanel />
    </div>
  )
}
