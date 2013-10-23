require 'sourcify'
require 'active_support/inflector'
require 'destruct'
require 'paramix'
require 'binding_of_caller'
require 'sexp_transformer'

module Destructure

  include Paramix::Parametric

  parameterized do |params|
    @_destructure_bind_locals = params[:bind_locals]
  end

  def dmatch(x, &pat_block)
    dmatch_internal(x, pat_block.to_sexp, binding.of_caller(1), caller_locations(1,1)[0].label)
  end

  private ########################################

  def dmatch_internal(x, sexp, caller_binding, caller_location)
    env = dmatch_no_ostruct_sexp(x, sexp)
    return nil if env.nil?

    if bind_locals
      env.keys.each {|k| _destructure_set(k.name, env[k], caller_binding, caller_location)}
    end

    env.to_openstruct
  end

  def dmatch_no_ostruct_sexp(x, sexp)
    sp = sexp.to_a.last
    pat = SexpTransformer.transform(sp)
    Destruct::match(pat, x)
  end

  def _destructure_set(name, value, binding, caller)
    if binding.eval("defined? #{name}") == 'local-variable'
      # we can do this with Binding#local_variable_set when Ruby 2.1 is released
      $binding_temp = value
      binding.eval("#{name} = $binding_temp")
    else
      if self.respond_to? name
        raise "Cannot have pattern variable named '#{name}'. A method already exists with that name. Choose a different name, " +
                  "or pre-initialize a local variable that shadows the method."
      end
      @_destructure_env ||= {}
      @_destructure_env[caller] ||= {}
      @_destructure_env[caller][name] = value
    end
  end

  def method_missing(name, *args, &block)
    if bind_locals
      c = caller_locations(1,1)[0].label
      @_destructure_env ||= {}
      caller_hash = @_destructure_env[c]
      caller_hash && caller_hash.keys.include?(name) ? caller_hash[name] : super
    else
      super
    end
  end

  def bind_locals
    bind = self.class.instance_variable_get(:@_destructure_bind_locals)
    @bind_locals ||= bind.nil? ? true : bind
  end

end
