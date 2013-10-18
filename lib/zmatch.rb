require 'pmatch'
require 'binding_of_caller'

module Deconstruct

  def zmatch(x, &pat_block)
    e = pmatch_no_ostruct(x, &pat_block)
    b = binding.of_caller(1)
    c = caller_locations(1,1)[0].label
    e && e.keys.each {|k| _deconstruct_set(k.name, e[k], b, c)}
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

  def method_missing(name)
    c = caller_locations(1,1)[0].label
    caller_hash = @_deconstruct_env[c]
    caller_hash && caller_hash.keys.include?(name) ? caller_hash[name] : super
  end

end