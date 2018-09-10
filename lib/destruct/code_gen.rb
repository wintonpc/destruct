require 'stringio'

class Destruct
  module CodeGen
    def emitted
      @emitted ||= StringIO.new
    end

    def emit(str)
      emitted << str
      emitted << "\n"
    end
  end
end
