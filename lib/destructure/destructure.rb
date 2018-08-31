require_relative './sexp_transformer'
require 'ostruct'

class Destructure
  def destructure(obj, transformer, &block)
    context = Context.new(obj, transformer, eval('self', block.binding))
    context.instance_exec(&block)
  end

  class Context
    def initialize(obj, transformer, outer_self)
      @obj = obj
      @transformer = transformer
      @outer_self = outer_self
    end

    def match(pat=nil, &pat_proc)
      if pat && pat_proc
        raise "Cannot specify both a pattern and a pattern proc"
      end
      pat ||= @transformer.transform(pat_proc)
      env = DMatch.match(pat, @obj)
      set_env(env) if env
      !!env
    end

    def set_env(matched_env)
      matched_env.each_kv do |k, v|
        self.class.send(:define_method, k) { v }
      end
    end

    def method_missing(method, *args, &block)
      if @outer_self
        @outer_self.send(method, *args, &block)
      else
        super
      end
    end
  end
end

class Object
  private

  def destructure(obj, transformer=DMatch::SexpTransformer, &block)
    Destructure.new.destructure(obj, transformer, &block)
  end
end


