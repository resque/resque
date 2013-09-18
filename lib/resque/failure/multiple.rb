module Resque
  class Failure
    # A Failure backend that uses multiple backends
    # delegates all queries to the first backend
    class Multiple < Base

      class << self
        attr_accessor :classes
      end

      # @override (see Resque::Failure::Base::configure)
      # @param (see Resque::Failure::Base::configure)
      # @return (see Resque::Failure::Base::configure)
      def self.configure
        yield self
        Resque::Failure.backend = self
      end

      # @override (see Resque::Failure::Base#initialize)
      # @param (see Resque::Failure::Base#initialize)
      # @return (see Resque::Failure::Base#initialize)
      def initialize(*args)
        super
      end

      # @override (see Resque::Failure::Base#save)
      # @param (see Resque::Failure::Base#save)
      # @return (see Resque::Failure::Base#save)
      def self.save(failure)
        classes.each { |klass| klass.save(failure) }
      end

      # The number of failures.
      # @override (see Resque::Failure::Base::count)
      # @param (see Resque::Failure::Base::count)
      # @return (see Resque::Failure::Base::count)
      def self.count(*args)
        classes.first.count(*args)
      end

      # Returns an array of all failure objects, filtered by options
      # @override (see Resque::Failure::Base::all)
      # @param (see Resque::Failure::Base::all)
      # @return (see Resque::Failure::Base::all)
      def self.all(*args)
        classes.first.all(*args)
      end

      # Returns a paginated array of failure objects.
      # @override (see Resque::Failure::Base::all)
      # @param (see Resque::Failure::Base::all)
      # @return (see Resque::Failure::Base::all)
      def self.slice(*args)
        classes.first.slice(*args)
      end

      # A URL where someone can go to view failures.
      # @override (see Resque::Failure::Base::url)
      # @param (see Resque::Failure::Base::url)
      # @return (see Resque::Failure::Base::url)
      def self.url
        classes.first.url
      end

      # Clear all failure objects
      # @override (see Resque::Failure::Base::clear)
      # @param (see Resque::Failure::Base::clear)
      # @return (see Resque::Failure::Base::clear)
      def self.clear(queue = nil)
        classes.first.clear(queue)
      end

      # @override (see Resque::Failure::Base::requeue)
      # @param (see Resque::Failure::Base::requeue)
      # @return (see Resque::Failure::Base::requeue)
      def self.requeue(*args)
        classes.first.requeue(*args)
      end

      # @override (see Resque::Failure::Base::remove)
      # @param (see Resque::Failure::Base::remove)
      # @return (see Resque::Failure::Base::remove)
      def self.remove(*args)
        classes.each { |klass| klass.remove(*args) }
      end
    end
  end
end
