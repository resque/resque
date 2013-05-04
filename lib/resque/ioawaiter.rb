module Resque
  class IOAwaiter
    def await
      rd, wr = IO.pipe
      trap('CONT') {
        wr.write 'x'
        wr.close
      }

      rd.read 1
      rd.close

      trap('CONT', 'DEFAULT')
    end
  end
end
