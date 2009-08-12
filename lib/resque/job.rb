class Resque
  class Job
    attr_accessor :worker

    def initialize(resque, queue, payload)
      @resque = resque
      @queue = queue
      @payload = payload
    end

    def perform
      object.perform if object && object.respond_to?(:perform)
    end

    def fail(exception, worker = nil)
      @resque.push "failed", \
        :failed_at => Time.now,
        :payload   => @payload,
        :error     => exception.to_s,
        :backtrace => exception.backtrace,
        :worker    => worker.inspect,
        :queue     => @queue
    end

    def done
      :ok
    end

    def object
      @object ||= objectify(@payload)
    end

    def objectify(payload)
      if payload.is_a?(Hash) && payload['class']
        constantize(payload['class']).new(*payload['args'])
      else
        raise "failed: #{inspect}"
      end
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
  end
end
