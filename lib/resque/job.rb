class Resque
  class Job
    attr_accessor :worker
    attr_reader   :queue, :payload

    def initialize(queue, payload)
      @queue = queue
      @payload = payload
    end

    def self.create(queue, klass, *args)
      resque.push(queue, :class => klass.to_s, :args => args)
    end

    def self.reserve(queue)
      return unless payload = resque.pop(queue)
      new(queue, payload)
    end

    def perform
      return unless object && object.respond_to?(:perform)
      args ? object.perform(*args) : object.perform
    end

    def object
      @object ||= objectify(@payload)
    end

    def args
      @payload['args']
    end

    def objectify(payload)
      if payload.is_a?(Hash) && payload['class']
        constantize(payload['class'])
      end
    end

    def fail(exception)
      resque.redis_push :failed, \
        :failed_at => Time.now.to_s,
        :payload   => payload,
        :error     => exception.to_s,
        :backtrace => exception.backtrace,
        :worker    => worker,
        :queue     => queue
    end

    def self.failed_size
      resque.redis_list_length(:failed)
    end

    def self.failed(start = 0, count = 1)
      resque.redis_list_range(:failed, start, count)
    end


    #
    # activesupport
    #

    def classify(dashed_word)
      dashed_word.split('-').each { |part| part[0] = part[0].chr.upcase }.join
    end

    def constantize(camel_cased_word)
      camel_cased_word = camel_cased_word.to_s

      if camel_cased_word.include?('-')
        camel_cased_word = classify(camel_cased_word)
      end

      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_get(name) || constant.const_missing(name)
      end
      constant
    end

    def self.resque
      @resque ||= Resque.new
    end

    def resque
      @resque ||= Resque.new
    end
  end
end
