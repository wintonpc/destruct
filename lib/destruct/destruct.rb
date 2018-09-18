# frozen_string_literal: true

require 'unparser'
require_relative 'rule_sets/destruct'
require_relative './code_gen'
require_relative './util'

class Proc
  def cached_source_location
    @cached_source_location ||= source_location # don't allocate a new array every time
  end
end

class Destruct
  include CodeGen

  NOTHING = make_singleton("#<NOTHING>")

  class << self
    def destructs_by_proc
      Thread.current[:destructs_by_proc] ||= {}
    end

    def destruct(obj, rule_set=Destruct::RuleSets::StandardPattern, &block)
      if rule_set.is_a?(Class)
        rule_set = rule_set.instance
      end
      key = block.cached_source_location
      d = destructs_by_proc.fetch(key) do
        destructs_by_proc[key] = Destruct.new.compile(block, rule_set)
      end
      d.(obj, block)
    end
  end

  def compile(pat_proc, tx)
    case_expr = RuleSets::Destruct.transform(&pat_proc)
    source_file = pat_proc.source_location[0]
    input_name = case_expr.value ? Unparser.unparse(case_expr.value).to_sym : :_input
    emit_lambda("_x", "_obj_with_binding") do
      show_code_on_error do
        case_expr.whens.each do |w|
          w.preds.each do |pred|
            pat = tx.transform(pred, binding: pat_proc.binding)
            cp = Compiler.compile(pat)
            if_str = w == case_expr.whens.first && pred == w.preds.first ? "if" : "elsif"
            emit "#{if_str} _env = #{get_ref(cp.generated_code)}.proc.(_x, _obj_with_binding)"
            emit_body(w.body, input_name, cp.var_names, source_file)
          end
        end
        if case_expr.else_body
          emit "else"
          emit_body(case_expr.else_body, input_name, [], source_file)
        end
        emit "end"
      end
    end
    filename = "Destruct for #{pat_proc}"
    g = generate(filename)
    show_code(g)
    g.proc
  end

  def emit_body(body, input_name, var_names, source_file_path)
    redirected, needs_binding = redirect(body, [input_name, *var_names])
    params = [input_name, *var_names.map(&:to_s)]
    params << "_binding" if needs_binding
    code = StringIO.new
    code.puts "lambda do |#{params.join(", ")}|"
    code.puts Unparser.unparse(redirected)
    code.puts "end"
    code = code.string
    puts code
    args = ["_x", *var_names.map { |name| "_env.#{name}" }]
    args << "_obj_with_binding.binding" if needs_binding
    body_proc = get_ref(eval(code, nil, source_file_path, body.location.line - 1))
    emit "#{body_proc}.(#{args.join(", ")})"
  end

  def self.match(pat, x, binding=nil)
    Compiler.compile(pat).match(x, binding)
  end

  def self.match2(x, binding=nil, &pat_proc)
    match(RuleSets::StandardPattern.transform(binding: binding, &pat_proc), x, binding)
  end

  private def redirect(node, var_names)
    @needs_binding = false
    [redir(node, var_names), @needs_binding]
  end

  include RuleSets::Helpers

  private def redir(node, var_names)
    if !node.is_a?(Parser::AST::Node)
      node
    elsif (e = match(n(any(:lvar, :ivar), [v(:name)]), node)) && !var_names.include?(e[:name])
      @needs_binding = true
      m(:send, m(:lvar, :_binding), :eval, m(:str, e[:name].to_s))
    elsif (e = match(n(:send, [nil, v(:meth), s(:args)]), node)) && !var_names.include?(e[:meth])
      @needs_binding = true
      self_expr = m(:send, m(:lvar, :_binding), :receiver)
      m(:send, self_expr, :send, m(:sym, e[:meth]), *e[:args].map { |c| redir(c, var_names) })
    elsif e = match(n(:block, [v(:recv), v(:args), v(:block)]), node)
      bound_vars = e[:args].children.map { |c| arg_name(c) }
      node.updated(nil, [redir(e[:recv], var_names), e[:args], redir(e[:block], var_names + bound_vars)])
    else
      node.updated(nil, node.children.map { |c| redir(c, var_names) })
    end
  end

  private def match(pat, x)
    Destruct.match(pat, x)
  end

  def arg_name(a)
    if a.type == :arg
      a.children[0]
    else
      raise "Unexpected arg: #{a}"
    end
  end

  def m(type, *children)
    Parser::AST::Node.new(type, children)
  end
end

def destruct(obj, rule_set=Destruct::RuleSets::StandardPattern, &block)
  Destruct.destruct(obj, rule_set, &block)
end
