# frozen_string_literal: true

module Redis
  class Inspector
    DEFAULT_PAGE_SIZE = 100

    def initialize(client:)
      @client = client
    end

    def scan(pattern:, db:, cursor:, page_size: DEFAULT_PAGE_SIZE)
      @client.select(db.to_i)
      next_cursor, keys = @client.scan(cursor.to_i, match: pattern, count: page_size)

      data = keys.map do |key|
        {
          key: key,
          type: @client.type(key),
          ttl: @client.ttl(key),
          size: key_size(key)
        }
      end

      {
        keys: data,
        next_cursor: next_cursor.to_i,
        has_more: next_cursor.to_i != 0
      }
    end

    def fetch(key:, db:)
      @client.select(db.to_i)
      key_type = @client.type(key)

      {
        key: key,
        type: key_type,
        ttl: @client.ttl(key),
        value: key_value(key, key_type),
        size: key_size(key)
      }
    end

    def delete(key:, db:)
      @client.select(db.to_i)
      @client.del(key)
    end

    def info
      @client.info
    end

    private

    def key_value(key, type)
      case type
      when 'string'
        @client.get(key)
      when 'hash'
        @client.hgetall(key)
      when 'list'
        @client.lrange(key, 0, -1)
      when 'set'
        @client.smembers(key)
      when 'zset'
        @client.zrange(key, 0, -1, with_scores: true)
      else
        'Unknown type'
      end
    end

    def key_size(key)
      case @client.type(key)
      when 'string'
        @client.strlen(key)
      when 'hash'
        @client.hlen(key)
      when 'list'
        @client.llen(key)
      when 'set'
        @client.scard(key)
      when 'zset'
        @client.zcard(key)
      else
        0
      end
    end
  end
end

