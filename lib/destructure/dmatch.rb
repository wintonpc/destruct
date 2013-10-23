require 'destructure/env'
require 'destructure/types'

class DMatch
  def self.match(pat, x)
    DMatch.new(Env.new).match(pat, x)
  end

  def self._
    Wildcard.instance
  end

  def initialize(env)
    @env = env
  end

  def match(pat, x)
    case
      when pat.is_a?(Wildcard); @env
      when pat.is_a?(Pred) && pat.test(x); @env
      when pat.is_a?(FilterSplat); match_filter_splat(pat, x)
      when pat.is_a?(SelectSplat); match_select_splat(pat, x)
      when pat.is_a?(Splat); match_splat(pat, x)
      when pat.is_a?(Var) && pat.test(x); match_var(pat, x)
      when pat.is_a?(Obj) && pat.test(x) && all_field_patterns_match(pat, x); @env
      when pat.is_a?(String) && pat == x; @env
      when pat.is_a?(Regexp); match_regexp(pat, x)
      when hash(pat, x) && all_keys_match(pat, x); @env
      when enumerable(pat, x); match_enumerable(pat, x)
      when pat == x; @env
      else; nil
    end
  end

  private ###########################################################

  def all_keys_match(pat, x)
    all_match(pat.keys.map { |k| x.keys.include?(k) && match(pat[k], x[k]) })
  end

  def match_regexp(pat, x)
    m = pat.match(x)
    m && @env.merge!(Hash[pat.named_captures.keys.map { |k| [Var.new(k.to_sym), m[k]] }])
  end

  def all_field_patterns_match(pat, x)
    all_match(pat.fields.keys.map { |name| x.respond_to?(name) && match(pat.fields[name], x.send(name)) })
  end

  def match_var(pat, x)
    @env.bind(pat, x)
  end

  def match_splat(pat, x)
    @env.bind(pat, enumerable(x) ? x : [x])
  end

  def match_select_splat(pat, x)
    x_match_and_env = x.map { |z| [z, DMatch::match(pat.pattern, z)] }.reject { |q| q.last.nil? }.first
    if x_match_and_env
      x_match, env = x_match_and_env
      @env.bind(pat, x_match) && @env.merge!(env)
    else
      nil
    end
  end

  def match_filter_splat(pat, x)
    @env.bind(pat, x.map { |z| [z, match(pat.pattern, z)] }.reject { |q| q.last.nil? }.map { |q| q.first })
  end

  def match_enumerable(pat, x)
    case
      when (parts = decompose_splatted_enumerable(pat))
        pat_before, pat_splat, pat_after = parts
        x_before = x.take(pat_before.length)
        if pat_after.any?
          splat_len = len(x) - pat_before.length - pat_after.length
          return nil if splat_len < 0
          x_splat = x.drop(pat_before.length).take(splat_len)
        else
          x_splat = x.drop(pat_before.length)
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
  end

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
    all_match(pat.zip(x).map{|a| match(*a)}) ? @env : nil
  end

  def enumerable(*xs)
    xs.all?{|x| x.is_a?(Enumerable)}
  end

  def hash(*xs)
    xs.all?{|x| x.is_a?(Hash)}
  end

  def all_match(xs)
    xs.all?{|x| x.is_a?(Env)}
  end

  class Wildcard
    include Singleton
  end
end