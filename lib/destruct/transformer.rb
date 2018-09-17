# frozen_string_literal: true

require 'active_support/core_ext/object/deep_dup'
require 'destruct/types'
require 'stringio'
require_relative './compiler'

class Destruct
  class Transformer
    DEBUG = true
    Rec = Struct.new(:input, :output, :subs, :is_recurse, :rule)
    class NotApplicable < RuntimeError; end
    class Accept < RuntimeError
      attr_reader :result

      def initialize(result=nil)
        @result = result
      end
    end

    Rule = Struct.new(:pat, :template, :constraints)
    class Rule
      def to_s
        s = "#{pat.inspect}"
        if constraints&.any?
          s += " where #{constraints}"
        end
        s
      end
      alias_method :inspect, :to_s
    end

    Code = Struct.new(:code)
    class Code
      def to_s
        "#<Code: #{code}>"
      end
      alias_method :inspect, :to_s
    end

    class << self
      def transform(x, rule_set, binding)
        txr = Transformer.new(rule_set, binding)
        result = txr.transform(x)
        if DEBUG
          puts "\nRules:"
          dump_rules(rule_set.rules)
          puts "\nTransformations:"
          tmp = StringIO.new
          dump_rec(txr.rec, f: tmp)
          w = tmp.string.lines.map(&:size).max
          dump_rec(txr.rec, width: w)
        end
        result
      end

      def dump_rules(rules)
        rules.each do |rule|
          puts "  #{rule}"
        end
      end

      def dump_rec(rec, depth=0, width: nil, f: $stdout)
        return if rec.input == rec.output && (rec.subs.none? || rec.is_recurse)
        indent = "│  " * depth
        if width
          f.puts "#{indent}┌ #{(format(rec.input) + "  ").ljust(width - (depth * 3), "┈")}┈┈┈ #{rec.rule&.pat || "(no rule matched)"}"
        else
          f.puts "#{indent}┌ #{format(rec.input)}"
        end
        rec.subs.each { |s| dump_rec(s, depth + 1, width: width, f: f) }
        f.puts "#{indent}└ #{format(rec.output)}"
      end

      def format(x)
        if x.is_a?(Parser::AST::Node)
          x.to_s.gsub(/\s+/, " ")
        elsif x.is_a?(Array)
          "[#{x.map { |v| format(v) }.join(", ")}]"
        elsif x.is_a?(Hash)
          "{#{x.map { |k, v| "#{k}: #{format(v)}" }.join(", ")}}"
        else
          x.inspect
        end
      end

      def unparse(x)
        if x.is_a?(Code)
          x.code
        elsif x.is_a?(Parser::AST::Node)
          Unparser.unparse(x)
        elsif x.is_a?(Var)
          x.name.to_s
        else
          x
        end
      end

      def quote(&block)
        RuleSets::Quote.transform(&block)
      end
    end

    attr_reader :rec

    def initialize(rule_set, binding)
      @rules = rule_set.rules
      @binding = binding
      @rec_stack = []
    end

    def push_rec(input)
      parent = @rec_stack.last
      current = Rec.new(input, nil, [])
      @rec ||= current
      @rec_stack.push(current)
      parent.subs << current if parent
    end

    def pop_rec(output, rule=nil)
      current = current_rec
      current.output = output
      current.is_recurse = @recursing
      current.rule = rule
      @rec_stack.pop
      output
    end

    def recursing
      last = @recursing
      @recursing = true
      yield
    ensure
      @recursing = last
    end

    def current_rec
      @rec_stack.last
    end

    def transform(x)
      push_rec(x)
      @rules.each do |rule|
        begin
          if rule.pat.is_a?(Class) && x.is_a?(rule.pat)
            applied = pop_rec(apply_template(x, rule, [x]), rule)
            return continue_transforming(x, applied)
          elsif e = Destruct.match(rule.pat, x)
            args = {}
            if e.is_a?(Env)
              e.env_each do |k, v|
                raw_key = :"raw_#{k}"
                raw_key = proc_has_kw(rule.template, raw_key) && raw_key
                val = v.transformer_eql?(x) || raw_key ? v : transform(v) # don't try to transform if we know we won't get anywhere (prevent stack overflow); template might guard by raising NotApplicable
                args[raw_key || k] = val
              end
            end
            applied = pop_rec(apply_template(x, rule, [], args), rule)
            return continue_transforming(x, applied)
          end
        rescue NotApplicable
          # continue to next rule
        end
      end

      # no rule matched
      pop_rec(x)
    rescue => e
      begin
        pop_rec("<error>")
      rescue
        # eat it
      end
      raise
    end

    def continue_transforming(old_x, x)
      if x.transformer_eql?(old_x)
        x
      else
        recursing { transform(x) }
      end
    end

    def apply_template(x, rule, args=[], kws={})
      if proc_has_kw(rule.template, :binding)
        kws[:binding] = @binding
      end
      if proc_has_kw(rule.template, :transform)
        kws[:transform] = method(:transform)
      end
      begin
        if kws.any?
          rule.template.(*args, **kws)
        else
          rule.template.(*args)
        end
      rescue Accept => accept
        accept.result || x
      end
    end

    def proc_has_kw(proc, kw)
      proc.parameters.include?([:key, kw]) || proc.parameters.include?([:keyreq, kw])
    end
  end
end

def quote(&block)
  Destruct::Transformer.quote(&block)
end

def unparse(expr)
  Destruct::Transformer.unparse(expr)
end
