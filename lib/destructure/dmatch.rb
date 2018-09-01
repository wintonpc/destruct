# frozen_string_literal: true

require 'destructure/env'
require 'destructure/types'

class DMatch
  def self.match(pat, x)
    DMatch.new.match(Pattern.get_cooked(pat), x)
  end

  def self.last_match_attempt(pat, x)
    DMatch.new.last_match_attempt(Pattern.get_cooked(pat), x)
  end

  def self._
    Wildcard.instance
  end

  def initialize(env=nil)
    @env = env || Env.new
  end

  def match(pat, x)
    @last_match_attempt = [pat, x] if @track_last_match_attempt
    case
    when pat.is_a?(Wildcard); @env
    when pat.is_a?(Pred) && pat.test(x, @env); @env
    when pat.is_a?(FilterSplat); match_filter_splat(pat, x)
    when pat.is_a?(SelectSplat); match_select_splat(pat, x)
    when pat.is_a?(Splat); match_splat(pat, x)
    when pat.is_a?(Var) && pat.test(x, @env); match_var(pat, x)
    when pat.is_a?(Obj) && pat.test(x, @env) && all_field_patterns_match(pat, x); @env
    when pat.is_a?(String) && pat == x; @env
    when pat.is_a?(Regexp); match_regexp(pat, x)
    when pat.is_a?(Or); match_or(pat, x)
    when pat.is_a?(Hash) && x.is_a?(Hash) && all_keys_match(pat, x); @env
    when pat.is_a?(Enumerable) && x.is_a?(Enumerable); match_enumerable(pat, x)
    when pat == x; @env
    else; nil
    end
  end

  def last_match_attempt(pat, x)
    @track_last_match_attempt = true
    match(pat, x)
    @last_match_attempt
  end

  private ###########################################################

  def all_keys_match(pat, x)
    pat.keys.all? { |k| x.keys.include?(k) && match(pat[k], x[k]) }
  end

  def match_regexp(pat, x)
    m = pat.match(x.to_s)
    m && @env.merge!(Hash[pat.named_captures.keys.map { |k| [Var.new(k.to_sym), m[k]] }])
  end

  def all_field_patterns_match(pat, x)
    all_match(pat.fields.keys.map { |name| x.respond_to?(name) && match(pat.fields[name], x.send(name)) })
  end

  def match_var(pat, x)
    @env.bind(pat, x)
  end

  def match_or(pat, x)
    pat.patterns.lazy.map{|p| match(p, x)}.reject{|e| e.nil?}.first
  end

  def match_splat(pat, x)
    @env.bind(pat, x.is_a?(Enumerable) ? x : [x])
  end

  def match_select_splat(pat, x)
    x_match_and_env = x.map { |z| [z, DMatch.match(pat.pattern, z)] }.reject { |q| q.last.nil? }.first
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
    if pat.is_a?(SplattedEnumerable)
      pat_before = pat.before
      pat_splat = pat.splat
      pat_after = pat.after
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
    elsif len(pat) == len(x)
      match_enumerable_no_splats(pat, x)
    else
      nil
    end
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
    x.respond_to?(:size) ? x.size : x.count
  end

  def match_enumerable_no_splats(pat, x)
    if x.is_a?(Hash)
      match_hash_no_splats(pat, x)
    elsif x.is_a?(Array)
      match_array_no_splats(pat, x)
    else
      all_match(pat.zip(x).map{|a| match(*a)}) ? @env : nil
    end
  end

  def match_array_no_splats(pat, x)
    i = 0
    len = max(pat.size, x.size)
    while i < len
      r = match(pat[i], x[i])
      return nil unless r
      i += 1
    end
    @env
  end

  def match_hash_no_splats(pat, x)
    i = 0
    len = max(pat.size, x.size)
    while i < len
      r = match(pat.keys[i], x.keys[i])
      return nil unless r
      r = match(pat.values[i], x.values[i])
      return nil unless r
      i += 1
    end
    @env
  end

  def max (a, b)
    a > b ? a : b
  end

  def all_match(xs)
    xs.all?{|x| x.is_a?(Env)}
  end

  class Wildcard
    include Singleton
  end
end
