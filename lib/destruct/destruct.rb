# frozen_string_literal: true

require 'unparser'
require 'destruct/transformer/destruct'
require_relative './code_gen'

class Destruct
  include CodeGen

  class << self
    def destructs_by_proc
      Thread.current[:destructs_by_proc] ||= {}
    end

    def destruct(obj, transformer=Transformer::StandardPattern, &block)
      d = destructs_by_proc.fetch(block.cached_source_location) do
        destructs_by_proc[block.cached_source_location] = Destruct.new.compile(block, transformer)
      end
      d.(obj, block.binding)
    end
  end

  def compile(pat_proc, tx)
    case_expr = Transformer::Destruct.transform(tag_unmatched: false, &pat_proc)
    emit_lambda("_x", "_binding") do
      show_code_on_error do
        case_expr.whens.each do |w|
          pat = tx.transform(w.pred)
          cp = Compiler.compile(pat)
          if_str = w == case_expr.whens.first ? "if" : "elsif"
          emit "#{if_str} _env = #{get_ref(cp.compiled)}.(_x, _binding)"
          cp.var_names.each do |name|
            emit "#{name} = _env.#{name}"
          end
          redirected = redirect(w.body)
          emit Unparser.unparse(redirected)
        end
        if case_expr.else_body
          emit "else"
          emit Unparser.unparse(case_expr.else_body)
        end
        emit "end"
      end
    end
    g = generate
    show_code(g.code, fancy: false)
    g.proc
  end

  private def redirect(node)
    if !node.is_a?(Parser::AST::Node)
      node
    elsif node.type == :lvar
      n(:send, n(:lvar, :_binding), :eval, n(:str, node.children[0].to_s))
    else
      node.updated(nil, node.children.map { |c| redirect(c) })
    end
  end

  def n(type, *children)
    Parser::AST::Node.new(type, children)
  end
end
