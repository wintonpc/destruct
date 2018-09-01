# frozen_string_literal: true

require_relative './sexp_transformer'
require 'ostruct'

class Destructure
  class << self
    def destructure(obj, mode, transformer, &block)
      with_context do |context|
        context.reset(obj, transformer, block.binding)
        context.instance_exec(&block)
      end
    end

    private

    def with_context
      # instance_exec creates a singleton class for the receiver if one does not already exist.
      # The singleton class occupies 456 bytes of memory. If we created a new Context for each
      # call, a class would be allocated each time, which is not optimal.
      # Instead, draw from a pool of contexts. The pool size limits destructure nesting;
      # 100 should be plenty.
      contexts = Thread.current[:destructure_contexts] ||= begin
        cs = Array.new(100) { Context.new }
        cs.each(&:singleton_class)
        cs
      end
      context = contexts.pop
      begin
        yield context
      ensure
        contexts.push(context)
      end
    end
  end

  class Context
    def reset(obj, transformer, outer_binding)
      @obj = obj
      @transformer = transformer
      @outer_binding = outer_binding
      @outer_self = outer_binding.receiver
      @matched_env = nil
    end

    def match(pat=nil, &pat_proc)
      if pat && pat_proc
        raise "Cannot specify both a pattern and a pattern proc"
      end
      pat ||= @transformer.transform(pat_proc)
      env = DMatch.match(pat, @obj, @outer_binding)
      set_env(env) if env
      !!env
    end

    def set_env(matched_env)
      @matched_env = matched_env
    end

    def method_missing(method, *args, &block)
      @matched_env.fetch(method) do
        if @outer_self
          @outer_self.send(method, *args, &block)
        else
          super
        end
      end
    end
  end
end

class Object
  private

  def destructure(obj, mode=:silent, transformer=DMatch::SexpTransformer, &block)
    Destructure.destructure(obj, mode, transformer, &block)
  end
end


