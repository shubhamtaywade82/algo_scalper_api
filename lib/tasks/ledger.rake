# frozen_string_literal: true

namespace :ledger do
  desc 'Seed chart of accounts and opening paper cash balance'
  task seed: :environment do
    Ledger::Seeder.seed_accounts!
    Ledger::Seeder.seed_opening_balance!
    puts 'Ledger seeded.'
  end

  desc 'Backfill paper ledger journals from exited position_trackers'
  task backfill_paper: :environment do
    Ledger::Seeder.ensure_ready!

    scope = PositionTracker.paper.where(status: :exited).order(:id)
    puts "Backfilling #{scope.count} exited paper positions..."

    scope.find_each do |tracker|
      next if LedgerJournalEntry.exists?(idempotency_key: "entry:#{tracker.id}")

      Ledger::EntryPoster.post!(
        tracker: tracker,
        fill_price: tracker.entry_price,
        quantity: tracker.quantity,
        order_no: tracker.order_no
      )
      Ledger::ExitPoster.post!(tracker: tracker, exit_price: tracker.exit_price)
      print '.'
    end

    puts "\nBackfill complete."
  end

  desc 'Print ledger vs legacy wallet reconciliation'
  task reconcile: :environment do
    result = Ledger::BalanceChecker.compare_paper_wallet
    puts result.inspect
  end
end
