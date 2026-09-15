# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::TelegramNotifier do
  let(:notifier) { described_class.instance }

  describe "#notify_daily_profit_target_once" do
    let(:redis_mock) { instance_double(Redis) }

    before do
      allow(TelegramNotifier).to receive(:enabled?).and_return(true)
      allow(AlgoConfig).to receive(:fetch).and_return(
        telegram: { enabled: true, notify_daily_profit_target: true }
      )
      allow(Redis).to receive(:new).and_return(redis_mock)
      allow(notifier).to receive(:send_message)
    end

    context "when Redis SET NX succeeds once then key exists" do
      before do
        allow(redis_mock).to receive(:set).and_return(true, false)
      end

      it "sends Telegram only on the first call" do
        notifier.notify_daily_profit_target_once(global_daily_profit: 6000, max_daily_profit: 5000)
        notifier.notify_daily_profit_target_once(global_daily_profit: 6000, max_daily_profit: 5000)

        expect(notifier).to have_received(:send_message).once
      end
    end

    context "when notify_daily_profit_target is false" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          telegram: { enabled: true, notify_daily_profit_target: false }
        )
      end

      it "does not send" do
        allow(redis_mock).to receive(:set)

        notifier.notify_daily_profit_target_once(global_daily_profit: 6000, max_daily_profit: 5000)

        expect(notifier).not_to have_received(:send_message)
        expect(redis_mock).not_to have_received(:set)
      end
    end

    context "when Telegram is disabled" do
      before do
        allow(TelegramNotifier).to receive(:enabled?).and_return(false)
      end

      it "does not send" do
        notifier.notify_daily_profit_target_once(global_daily_profit: 6000, max_daily_profit: 5000)

        expect(notifier).not_to have_received(:send_message)
      end
    end
  end

  describe "formatting and parse_mode" do
    before do
      allow(ENV).to receive(:fetch).with("TELEGRAM_CHAT_ID", nil).and_return("12345")
      allow(ENV).to receive(:fetch).with("TELEGRAM_BOT_TOKEN", nil).and_return("fake_token")
      allow(TelegramNotifier).to receive(:post).and_return(instance_double(Net::HTTPSuccess))
    end

    it "formats inline code containing underscores into HTML code tags" do
      input = "verify your `CLIENT_ID`, `DHAN_PIN`, and `DHAN_TOTP_SECRET`"
      formatted = Telegram::Formatter.to_html(input)
      expect(formatted).to include("<code>CLIENT_ID</code>", "<code>DHAN_PIN</code>", "<code>DHAN_TOTP_SECRET</code>")
    end

    it "restores placeholders cleanly without leaking tokens" do
      input = "verify your `CLIENT_ID`, `DHAN_PIN`, and `DHAN_TOTP_SECRET`"
      formatted = Telegram::Formatter.to_html(input)
      expect(formatted).not_to match(/@@|%%/)
    end

    it "sets parse_mode to HTML when using formatter even if Markdown was requested" do
      TelegramNotifier.send_message("Hello `test_code`", parse_mode: "Markdown")

      expect(TelegramNotifier).to have_received(:post).with(
        "sendMessage",
        hash_including(chat_id: "12345", parse_mode: "HTML")
      )
    end
  end
end
