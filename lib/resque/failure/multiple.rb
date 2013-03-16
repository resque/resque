module Resque
  module Failure
    # A Failure backend that uses multiple backends
    # delegates all queries to the first backend
    class Multiple < Base

      class << self
        attr_accessor :classes
      end

      def self.configure
        yield self
        Resque::Failure.backend = self
      end

      def initialize(*args)
        super
        @backends = self.class.classes.map {|klass| klass.new(*args)}
      end

      def save
        @backends.each(&:save)
      end

      # The number of failures.
      def self.count(*args)
        classes.first.count(*args)
      end

      # Returns a paginated array of failure objects.
      def self.all(*args)
        classes.first.all(*args)
      end

      # Iterate across failed objects
      def self.each(*args, &block)
        classes.first.each(*args, &block)
      end

      # A URL where someone can go to view failures.
      def self.url
        classes.first.url
      end

      # Clear all failure objects
      def self.clear(*args)
        classes.first.clear(*args)
      end

      def self.requeue(*args)
        classes.first.requeue(*args)
      end

      def self.remove(index)
        classes.each { |klass| klass.remove(index) }
      end
    end
  end
end
