require_relative './sexp_transformer'
require 'ostruct'

class Destructure
  def destructure(obj, &block)
    context = Context.new(obj, eval('self', block.binding))
    context.instance_exec(&block)
  end

  class Context
    def initialize(obj, outer_self)
      @obj = obj
      @outer_self = outer_self
    end

    def match(&pat)
      env = DMatch.match(DMatch::SexpTransformer.transform(pat), @obj)
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

  def destructure(obj, &block)
    Destructure.new.destructure(obj, &block)
  end
end


