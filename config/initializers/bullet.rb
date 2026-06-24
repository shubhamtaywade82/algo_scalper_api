# frozen_string_literal: true

if defined?(Bullet) && Rails.env.development?
  Bullet.enable = true
  Bullet.alert = false
  Bullet.bullet_logger = true
  Bullet.console = false
  Bullet.rails_logger = true
  Bullet.add_footer = false
  Bullet.unused_eager_loading_enable = false
end
