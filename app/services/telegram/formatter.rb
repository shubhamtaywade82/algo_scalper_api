# app/services/telegram/formatter.rb
require "cgi"

module Telegram
  class Formatter
    TELEGRAM_LIMIT = 4096

    class << self
      def to_html(text)
        return "" if text.nil? || text.strip.empty?

        normalized = text.gsub("\r\n", "\n")

        # 1️⃣ Protect triple backtick code blocks
        code_blocks = []
        normalized = normalized.gsub(/```(.*?)```/m) do
          code_blocks << $1
          "%%CODE_BLOCK_#{code_blocks.size - 1}%%"
        end

        # 2️⃣ Protect inline code
        inline_codes = []
        normalized = normalized.gsub(/`([^`]+)`/) do
          inline_codes << $1
          "%%INLINE_CODE_#{inline_codes.size - 1}%%"
        end

        # 3️⃣ Escape everything
        escaped = CGI.escapeHTML(normalized)

        # 4️⃣ Format headings first
        formatted = format_headings(escaped)

        # 5️⃣ Format blockquotes
        formatted = format_blockquotes(formatted)

        # 6️⃣ Format lists
        formatted = format_lists(formatted)

        # 7️⃣ Inline formatting
        formatted = apply_inline_formatting(formatted)

        # 8️⃣ Restore inline code
        inline_codes.each_with_index do |code, i|
          formatted.gsub!(
            "%%INLINE_CODE_#{i}%%",
            "<code>#{CGI.escapeHTML(code)}</code>"
          )
        end

        # 9️⃣ Restore code blocks
        code_blocks.each_with_index do |code, i|
          formatted.gsub!(
            "%%CODE_BLOCK_#{i}%%",
            "<pre><code>#{CGI.escapeHTML(code)}</code></pre>"
          )
        end

        truncate(formatted)
      end

      private

      # ---------- Headings ----------
      def format_headings(text)
        text
          .gsub(/^###\s*(.+)$/) { "<b>#{strip_md($1)}</b>" }
          .gsub(/^####\s*(.+)$/) { "<b>#{strip_md($1)}</b>" }
      end

      # ---------- Blockquotes ----------
      def format_blockquotes(text)
        text.gsub(/^&gt;\s?(.*)$/) do
          "<blockquote>#{$1}</blockquote>"
        end
      end

      # ---------- Lists ----------
      def format_lists(text)
        text
          .gsub(/^\d+\.\s+(.+)$/) { "• #{$1}" }
          .gsub(/^\-\s+(.+)$/) { "• #{$1}" }
      end

      # ---------- Inline formatting ----------
      def apply_inline_formatting(text)
        text
          # bold
          .gsub(/\*\*(.+?)\*\*/, '<b>\1</b>')
          # italic
          .gsub(/_(?!\s)(.+?)(?<!\s)_/, '<i>\1</i>')
          # strikethrough
          .gsub(/~~(.+?)~~/, '<s>\1</s>')
      end

      def strip_md(text)
        text.gsub(/\*\*(.+?)\*\*/, '\1')
      end

      def truncate(text)
        return text if text.length <= TELEGRAM_LIMIT
        text[0...TELEGRAM_LIMIT - 25] + "<b>\n…truncated</b>"
      end
    end
  end
end
