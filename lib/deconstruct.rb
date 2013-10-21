require 'sourcify'
require 'active_support/inflector'
require 'decons'
require 'paramix'
require 'binding_of_caller'

module Deconstruct

  include Paramix::Parametric

  parameterized do |params|
    @_deconstruct_bind_locals = params[:bind_locals]
  end

  def dmatch(x, &pat_block)
    if bind_locals.nil? || bind_locals
      e = dmatch_no_ostruct(x, &pat_block)
      b = binding.of_caller(1)
      c = caller_locations(1,1)[0].label
      return nil if e.nil?
      e.keys.each {|k| _deconstruct_set(k.name, e[k], b, c)}
      e.to_openstruct
    else
      e = dmatch_no_ostruct(x, &pat_block)
      e && e.to_openstruct
    end
  end

  def method_missing(name, *args, &block)
    if bind_locals
      c = caller_locations(1,1)[0].label
      caller_hash = @_deconstruct_env[c]
      caller_hash && caller_hash.keys.include?(name) ? caller_hash[name] : super
    else
      super
    end
  end

  def transform(sp)
    _ = Decons::_
    klass_sym = Decons::Var.new(&method(:is_constant?))
    case
      when e = rmatch([:call, _, :_, _], sp); _
      when e = rmatch([:const, klass_sym], sp)
        make_obj(e[klass_sym], {})
      when e = rmatch([:call, _, klass_sym, [:arglist, [:hash, splat(:kv_sexps)]]], sp)
        kvs = transform_many(e[:kv_sexps])
        make_obj(e[klass_sym], Hash[*kvs])
      when e = rmatch([:call, _, klass_sym, [:arglist, splat(:field_name_sexps)]], sp)
        field_names = transform_many(e[:field_name_sexps])
        make_obj(e[klass_sym], Hash[field_names.map { |f| [f.name, var(f.name)] }])
      when e = rmatch([:call, _, var(:name), _], sp); var(e[:name])
      when e = rmatch([:lit, var(:value)], sp); e[:value]
      when e = rmatch([:true], sp); true
      when e = rmatch([:false], sp); false
      when e = rmatch([:nil], sp); nil
      when e = rmatch([:str, var(:s)], sp); e[:s]
      when e = rmatch([:array, splat(:items)], sp); e[:items].map(&method(:transform))
      when e = rmatch([:hash, splat(:kvs)], sp); Hash[*e[:kvs].map(&method(:transform))]
      when e = rmatch([:cvar, var(:name)], sp); splat(e[:name].to_s.sub(/^@@/, '').to_sym)
      else; raise "Unexpected sexp: #{sp.inspect}"
    end
  end

  private ########################################

  def bind_locals
    bind = self.class.instance_variable_get(:@_deconstruct_bind_locals)
    @bind_locals ||= bind.nil? ? true : bind
  end

  def dmatch_no_ostruct(x, &pat_block)
    sp = pat_block.to_sexp.to_a.last
    pat = transform(sp)
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

  def transform_many(xs)
    xs.map(&method(:transform))
  end

  def make_obj(klass_sym, field_map)
    Decons::Obj.of_type(klass_sym.to_s.constantize, field_map)
  end

  def is_constant?(x)
    x.is_a?(Symbol) && is_uppercase?(x.to_s[0])
  end

  def is_uppercase?(char)
    char == char.upcase
  end

  def rmatch(*args)
    Decons::match(*args)
  end

  def var(name)
    Decons::Var.new(name)
  end

  def splat(name)
    Decons::Splat.new(name)
  end

end
