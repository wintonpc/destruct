require 'unparser'
require 'destruct/transformer/destruct'
require_relative './code_gen'

class Destruct
  include CodeGen

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
    emit_lambda("x", "binding") do
      show_code_on_error do
      end
    end
    g = generate
    show_code(g.code)
    generate.proc
  end
end
