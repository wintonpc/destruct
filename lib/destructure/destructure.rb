require 'sourcify'
require 'active_support/inflector'
require 'paramix'
require 'binding_of_caller'
require 'destructure/dmatch'
require 'destructure/sexp_transformer'

module Destructure

  include Paramix::Parametric

  parameterized do |params|
    define_method(:bind_locals) do
      bind = params[:bind_locals]
      @bind_locals ||= bind.nil? ? true : bind
    end
  end

  def dbind(x, &pat_block)
    dbind_internal(x, pat_block.to_sexp(strip_enclosure: true, ignore_nested: true), binding.of_caller(1), caller_locations(1,1)[0].label)
  end

  private ########################################

  def bind_locals
    true
  end

  def dbind_internal(x, sexp, caller_binding, caller_location)
    env = dbind_no_ostruct_sexp(x, sexp, caller_binding)
    return nil if env.nil?

    if bind_locals
      env.keys.each {|k| _destructure_set(k.name, env[k], caller_binding, caller_location)}
    end

    env.to_openstruct
  end

  def dbind_no_ostruct_sexp(x, sexp, caller_binding)
    sp = sexp
    pat = SexpTransformer.transform(sp, caller_binding)
    DMatch::match(pat, x)
  end

  def _destructure_set(name, value, binding, caller)
    if name.is_a?(String) || binding.eval("defined? #{name}") == 'local-variable'
      $binding_temp = value
      binding.eval("#{name} = $binding_temp")
    else
      if binding.eval('self').respond_to?(name, true)
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

end
