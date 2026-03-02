# frozen_string_literal: true

base = defined?(ActionMailer::Base) ? ActionMailer::Base : Object

class ApplicationMailer < base
  if defined?(ActionMailer::Base)
    default from: 'from@example.com'
    layout 'mailer'
  end
end
