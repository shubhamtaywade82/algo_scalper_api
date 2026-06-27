# frozen_string_literal: true

module AlgoScalper
  class Application
    def self.root
      File.expand_path("../..", __dir__)
    end

    def self.load_services
      Dir[File.join(root, "app/services/**/*.rb")].sort.each { |f| require f }
    end
  end
end