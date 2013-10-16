require 'sourcify'

class Var
  attr_reader :name

  def initialize(name=nil)
    @name = name
  end
end

class Wildcard < Var
  def initialize
    super('_')
  end
end

class Env

  def env
    @env ||= {}
  end

  def [](identifier)
    raise 'identifier must be a Var' unless identifier.is_a? Var
    env[identifier] or raise "Identifier '#{identifier}' is not bound."
  end

  def []=(identifier, value)
    raise 'identifier must be a Var' unless identifier.is_a? Var
    raise "Identifier '#{identifier}' is already set to #{value}" if env.include?(identifier)
    env[identifier] = value
  end
end

class Runify
  def self.match(pat, x, env = Env.new)
    Runify.new(env).match(pat, x)
  end

  def initialize(env)
    @env = env
  end

  def match(pat, x)
    case
      when pat.is_a?(Var)
        @env[pat] = x
        @env
      when pat.is_a?(String) && pat == x; @env
      when enumerables(pat, x) &&
          pat.size == x.size &&
          no_nils(pat.zip(x).map{|a| match(*a)}); @env
      when hashes(pat, x) && no_nils(pat.keys.map{|k| match(pat[k], x[k])}); @env
      when pat == x; @env
      else; nil
    end
  end

  def enumerables(*xs)
    xs.all?{|x| x.is_a?(Enumerable)}
  end

  def hashes(*xs)
    xs.all?{|x| x.is_a?(Hash)}
  end

  def no_nils(xs)
    !xs.any?{|x| x.nil?}
  end
end