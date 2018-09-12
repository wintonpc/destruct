# frozen_string_literal: true

require 'unparser'
require 'destruct/transformer/destruct'
require_relative './code_gen'

class Proc
  def cached_source_location
    @cached_source_location ||= source_location # don't allocate a new array every time
  end
end

class Destruct
  include CodeGen

  class << self
    def destructs_by_proc
      Thread.current[:destructs_by_proc] ||= {}
    end

    def destruct(obj, transformer=Transformer::StandardPattern, &block)
      key = block.cached_source_location
      d = destructs_by_proc.fetch(key) do
        destructs_by_proc[key] = Destruct.new.compile(block, transformer)
      end
      d.(obj, block)
    end
  end

  def compile(pat_proc, tx)
    case_expr = Transformer::Destruct.transform_pattern_proc(&pat_proc)
    emit_lambda("_x", "_obj_with_binding") do
      show_code_on_error do
        case_expr.whens.each do |w|
          pat = tx.transform(w.pred)
          cp = Compiler.compile(pat)
          if_str = w == case_expr.whens.first ? "if" : "elsif"
          emit "#{if_str} _env = #{get_ref(cp.generated_code)}.proc.(_x, _obj_with_binding)"
          cp.var_names.each do |name|
            emit "#{name} = _env.#{name}"
          end
          redirected = redirect(w.body, cp.var_names)
          emit "_binding = _obj_with_binding.binding" if @needs_binding
          emit Unparser.unparse(redirected)
        end
        if case_expr.else_body
          emit "else"
          redirected = redirect(case_expr.else_body, [])
          emit "_binding = _obj_with_binding.binding" if @needs_binding
          emit Unparser.unparse(redirected)
        end
        emit "end"
      end
    end
    filename = "Destruct for #{pat_proc}"
    g = generate(filename)
    show_code(g)
    g.proc
  end

  private def redirect(node, var_names)
    if !node.is_a?(Parser::AST::Node)
      node
    elsif (node.type == :lvar || node.type == :ivar) && !var_names.include?(node.children[0])
      n(:send, n(:lvar, :_binding), :eval, n(:str, node.children[0].to_s))
    elsif node.type == :send && node.children[0].nil? && !var_names.include?(node.children[1])
      @needs_binding = true
      self_expr = n(:send, n(:lvar, :_binding), :receiver)
      n(:send, self_expr, :send, n(:sym, node.children[1]), *node.children[2..-1].map { |c| redirect(c, var_names) })
    else
      node.updated(nil, node.children.map { |c| redirect(c, var_names) })
    end
  end

  def n(type, *children)
    Parser::AST::Node.new(type, children)
  end
end

def destruct(obj, transformer=Destruct::Transformer::StandardPattern, &block)
  Destruct.destruct(obj, transformer, &block)
end
