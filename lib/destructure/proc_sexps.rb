# frozen_string_literal: true

require 'parser/current'
require 'unparser'

class DMatch
  class ProcSexps
    class << self
      def instance
        @instance ||= ProcSexps.new
      end

      def get(p)
        instance.get(p)
      end
    end

    def initialize
      @asts_by_file = {}
      @sexps_by_proc = {}
    end

    def get(p)
      @sexps_by_proc.fetch(p) do
        @sexps_by_proc[p] = begin
          file_path, line = *p.source_location
          ast = get_ast(file_path)
          node = find_proc(ast, line)
          node_to_sexp(node, p.binding)
        end
      end

    end

    private

    def get_ast(file_path)
      @asts_by_file.fetch(file_path) do
        @asts_by_file[file_path] = Parser::CurrentRuby.parse(File.read(file_path))
      end
    end

    def find_proc(node, line)
      return nil unless node.is_a?(Parser::AST::Node)
      if node.type == :block && node.location.line == line
        node.children[2]
      else
        node.children.lazy.map { |c| find_proc(c, line) }.reject(&:nil?).first
      end
    end

    def node_to_sexp(n, binding)
      if n.is_a?(Parser::AST::Node)
        if n.type == :dstr
          str = n.children.map do |c|
            if c.type == :str
              c.children[0]
            elsif c.type == :begin
              binding.eval(Unparser.unparse(c))
            end
          end.join
          [:str, str]
        else
          [n.type, *n.children.map { |c| node_to_sexp(c, binding) }]
        end
      else
        n
      end
    end
  end
end
