require 'env'
require 'types'

class Decons
  def self.match(pat, x)
    Decons.new(Env.new).match(pat, x)
  end

  def self._
    Wildcard.instance
  end

  def initialize(env)
    @env = env
  end

  def match(pat, x)
    pat.inspect
    case
      when pat.is_a?(Wildcard); @env
      when pat.is_a?(Pred) && pat.test(x); @env
      when pat.is_a?(FilterSplat)
        @env[pat] = x.map{|z| [z, match(pat.pattern, z)] }.reject{|q| q.last.nil?}.map{|q| q.first}
        @env
      when pat.is_a?(SelectSplat)
        x_match_and_env = x.map{|z| [z, Decons::match(pat.pattern, z)] }.reject{|q| q.last.nil?}.first
        if x_match_and_env
          x_match, env = x_match_and_env
          @env.merge!(env)
          @env[pat] = x_match
          @env
        else
          nil
        end
      when pat.is_a?(Splat)
        @env[pat] = enumerable(x) ? x : [x]
        @env
      when pat.is_a?(Var) && pat.test(x)
        @env[pat] = x
        @env
      when pat.is_a?(Obj) && pat.test(x) && no_nils(pat.fields.keys.map {|name| x.respond_to?(name) ? match(pat.fields[name], x.send(name)) : nil }); @env
      when pat.is_a?(String) && pat == x; @env
      when hash(pat, x) && no_nils(pat.keys.map{|k| match(pat[k], x[k])}); @env
      when enumerable(pat, x)
        case
          when (parts = decompose_splatted_enumerable(pat))
            pat_before, pat_splat, pat_after = parts
            x_before = x.take(pat_before.length)
            if pat_after.any?
              splat_len = len(x) - pat_before.length - pat_after.length
              return nil if splat_len < 0
              x_splat = x.drop(pat_before.length).take(splat_len)
            else
              x_splat =  x.drop(pat_before.length)
            end

            before_and_splat_result = match_enumerable_no_splats(pat_before, x_before) && match(pat_splat, x_splat)

            if before_and_splat_result && pat_after.any?
              # do this only if we have to, since it requires access to the end of the enumerable,
              # which doesn't work with infinite enumerables
              x_after = take_last(pat_after.length, x)
              match_enumerable_no_splats(pat_after, x_after)
            else
              before_and_splat_result
            end
          when len(pat) == len(x)
            match_enumerable_no_splats(pat, x)
          else; nil
        end
      when pat == x; @env
      else; nil
    end
  end

  private ###########################################################

  def decompose_splatted_enumerable(pat)
    before = []
    splat = nil
    after = []
    pat.each do |p|
      case
        when p.is_a?(Splat)
          if splat.nil?
            splat = p
          else
            raise "cannot have more than one splat in a single array: #{pat.inspect}"
          end
        when splat.nil?
          before.push(p)
        else
          after.push(p)
      end
    end

    splat && [before, splat, after]
  end

  def take_last(n, xs)
    result = []
    xs.reverse_each do |x|
      break if result.length == n
      result.unshift x
    end
    result
  end

  def len(x)
    x.respond_to?(:length) ? x.length : x.count
  end

  def match_enumerable_no_splats(pat, x)
    no_nils(pat.zip(x).map{|a| match(*a)}) ? @env : nil
  end

  def enumerable(*xs)
    xs.all?{|x| x.is_a?(Enumerable)}
  end

  def hash(*xs)
    xs.all?{|x| x.is_a?(Hash)}
  end

  def no_nils(xs)
    !xs.any?{|x| x.nil?} || nil
  end

  class Wildcard
    include Singleton
  end
end