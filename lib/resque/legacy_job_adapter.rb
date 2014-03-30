module Resque
  module LegacyJobAdapter
    def perform *args
      self.class.perform *args
    end
  end
end
