# frozen_string_literal: true

require 'active_support/core_ext/object/deep_dup'
require 'destruct/types'
require_relative './compiler'

class Destruct
  class Transformer
    DEBUG = true
    Rec = Struct.new(:input, :output, :subs, :is_recurse, :rule)
    class NotApplicable < RuntimeError; end

    Rule = Struct.new(:pat, :template, :constraints)
    class Rule
      def to_s
        s = "#{pat}"
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
          dump_rec(txr.rec)
        end
        result
      end

      def dump_rules(rules)
        rules.each do |rule|
          puts "  #{rule}"
        end
      end

      def dump_rec(rec, depth=0)
        return if rec.input == rec.output && (rec.subs.none? || rec.is_recurse)
        indent = "│  " * depth
        puts "#{indent}┌ #{format(rec.input)}"
        rec.subs.each { |s| dump_rec(s, depth + 1) }
        puts "#{indent}└ #{format(rec.output).ljust(80 - (depth * 3), "…")}………………#{rec.rule&.pat || "(no rule matched)"}"
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
      if x.is_a?(Array)
        pop_rec(x.map { |v| transform(v) })
      elsif x.is_a?(Hash)
        pop_rec(x.map { |k, v| [transform(k), transform(v)] }.to_h)
      else
        @rules.each do |rule|
          begin
            if rule.pat.is_a?(Class) && x.is_a?(rule.pat)
              applied = pop_rec(apply_template(rule, x, binding: @binding), rule)
              return recursing { transform(applied) }
            elsif e = Compiler.compile(rule.pat).match(x)
              args = {binding: @binding}
              if e.is_a?(Env)
                e.env_each do |k, v|
                  val = v == x ? v : transform(v) # don't try to transform if we know we won't get anywhere (prevent stack overflow); template might guard by raising NotApplicable
                  args[k] = val
                end
              end
              applied = pop_rec(apply_template(rule, **args), rule)
              return recursing { transform(applied) }
            end
          rescue NotApplicable
            # continue to next rule
          end
        end
        pop_rec(x)
      end
    rescue
      pop_rec("<error>")
      raise
    end

    def apply_template(rule, *args, **kws)
      if kws.any?
        if !rule.template.parameters.include?([:key, :binding]) && !rule.template.parameters.include?([:keyreq, :binding])
          kws = kws.dup
          kws.delete(:binding)
        end
        rule.template.(*args, **kws)
      else
        rule.template.(*args)
      end
    end
  end
end

def quote(&block)
  Destruct::Transformer.quote(&block)
end
