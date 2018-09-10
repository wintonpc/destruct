require 'unparser'
require 'destruct/transformer/destruct'

class Destruct
  class << self
    def destructs_by_proc
      Thread.current[:destructs_by_proc] ||= {}
    end

    def destruct(obj, &block)
      d = destructs_by_proc.fetch(block.cached_source_location) do
        destructs_by_proc[block.cached_source_location] = Destruct.new.compile(block)
      end
      d.(obj, block.binding)
    end
  end

  def compile(pat_proc)

  end
end
