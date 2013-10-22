require 'sourcify'
require 'active_support/inflector'
require 'decons'
require 'paramix'
require 'binding_of_caller'
require 'sexp_transformer'

module Deconstruct

  include Paramix::Parametric

  parameterized do |params|
    @_deconstruct_bind_locals = params[:bind_locals]
  end

  def dmatch(x, &pat_block)
    env = dmatch_no_ostruct(x, &pat_block)
    return nil if env.nil?

    if bind_locals
      b = binding.of_caller(1)
      c = caller_locations(1,1)[0].label
      env.keys.each {|k| _deconstruct_set(k.name, env[k], b, c)}
    end

    env.to_openstruct
  end

  private ########################################

  def dmatch_no_ostruct(x, &pat_block)
    sp = pat_block.to_sexp.to_a.last
    pat = SexpTransformer.transform(sp)
    Decons::match(pat, x)
  end

  def _deconstruct_set(name, value, binding, caller)
    if binding.eval("defined? #{name}") == 'local-variable'
      $binding_temp = value
      binding.eval("#{name} = $binding_temp")
    else
      if self.respond_to? name
        raise "Cannot have pattern variable named '#{name}'. A method already exists with that name. Choose a different name, " +
                  "or pre-initialize a local variable that shadows the method."
      end
      @_deconstruct_env ||= {}
      @_deconstruct_env[caller] ||= {}
      @_deconstruct_env[caller][name] = value
    end
  end

  def method_missing(name, *args, &block)
    if bind_locals
      c = caller_locations(1,1)[0].label
      @_deconstruct_env ||= {}
      caller_hash = @_deconstruct_env[c]
      caller_hash && caller_hash.keys.include?(name) ? caller_hash[name] : super
    else
      super
    end
  end

  def bind_locals
    bind = self.class.instance_variable_get(:@_deconstruct_bind_locals)
    @bind_locals ||= bind.nil? ? true : bind
  end

end
