require 'ast'

def make_singleton(inspect_str)
  obj = Object.new
  obj.define_singleton_method(:to_s) { inspect_str }
  obj.define_singleton_method(:inspect) { inspect_str }
  obj
end

class Object
  def primitive?
    is_a?(Numeric) || is_a?(String) || is_a?(Symbol) || is_a?(Regexp) || self == true || self == false || self == nil
  end
end

module Parser
  module AST
    class Node < ::AST::Node
      def to_s1
        to_s.gsub(/\s+/, " ")
      end
    end
  end
end

module Boot1
  # frozen_string_literal: true

  def require_glob(relative_path_glob)
    dir = File.dirname(caller[0].split(':')[0])
    Dir[File.join(dir, relative_path_glob)].sort.each { |file| require file }
  end

  # require_glob 'destruct/**/*.rb'
  # frozen_string_literal: true

  require 'parser/current'
  require 'unparser'

  class Destruct
    # Obtains the AST node for a given proc
    class ExprCache
      class << self
        def instance
          Thread.current[:__boot1_syntax_cache_instance__] ||= ExprCache.new
        end

        def get(p, &k)
          instance.get(p, &k)
        end
      end

      Region = Struct.new(:path, :begin_line, :begin_col, :end_line, :end_col)

      def initialize
        @asts_by_file = {}
        @exprs_by_proc = {}
      end

      # Obtains the AST node for a given proc. The node is found by using
      # Proc#source_location to reparse the source file and find the proc's node
      # on the appropriate line. If there are multiple procs on the same line,
      # procs and lambdas are preferred over blocks, and the first is returned.
      # If try_to_use is provided, candidate nodes are passed to the block for
      # evaluation. If the node is unacceptable, the block is expected to raise
      # InvalidPattern. The first acceptable block is returned.
      # If the proc was entered at the repl, we attempt to find it in the repl
      # history.
      # TODO: Use Region.begin_col to disambiguate. It's not straightforward:
      # Ruby's parser sometimes disagrees with the parser gem. The relative
      # order of multiple procs on the same line should be identical though.
      def get(p, &try_to_use)
        cache_key = p.source_location_id
        sexp = @exprs_by_proc[cache_key]
        return sexp if sexp

        ast, region = get_ast(Region.new(*p.source_region))
        candidate_nodes = find_proc(ast, region)
        # prefer lambdas and procs over blocks
        candidate_nodes = candidate_nodes.sort_by do |n|
          n.children[0].type == :send && (n.children[0].children[1] == :lambda ||
          n.children[0].children[1] == :proc) ? 0 : 1
        end.map { |n| n.children[2] }

        if !try_to_use
          @exprs_by_proc[cache_key] =
          if candidate_nodes.size > 1
            candidate_nodes.reject { |n| contains_block?(n) }.first # hack to deal with more than one per line
          else
            candidate_nodes.first
          end
        else
          tried_candidates = candidate_nodes.map do |n|
            begin
              try_to_use.(n)
            rescue InvalidPattern => e
              e
            end
          end
          first_good_idx = tried_candidates.find_index { |x| !x.is_a?(InvalidPattern) }
          if first_good_idx
            @exprs_by_proc[cache_key] = candidate_nodes[first_good_idx]
            tried_candidates[first_good_idx]
          else
            raise InvalidPattern.new(tried_candidates.last.pattern, Unparser.unparse(candidate_nodes.last))
          end
        end
      end

      private

      def contains_block?(node)
        if !node.is_a?(Parser::AST::Node)
          false
        elsif node.type == :block
          true
        else
          node.children.any? { |c| contains_block?(c) }
        end
      end

      def get_ast(region)
        if in_repl(region.path)
          start_offset = -1
          old_stderr = $stderr
          begin
            $stderr = File.open(IO::NULL, "w") # silence parse diagnostics
            code = Readline::HISTORY.to_a[start_offset..-1].join("\n")
            [Parser::CurrentRuby.parse(code), Region.new(region.path, 1, 0, 1, 0)]
          rescue Parser::SyntaxError
            start_offset -= 1
            retry
          ensure
            $stderr = old_stderr
          end
        else
          ast = @asts_by_file.fetch(region.path) do
            path = region.path
            code =
            if path.is_a?(Array) && File.basename(path.first, ".rb") =~ /boot(\d+)?/
              $boot_code.fetch(File.basename(path.first, ".rb"))
            else
              File.read(path)
            end
            @asts_by_file[path] = Parser::CurrentRuby.parse(code)
          end
          [ast, region]
        end
      end

      def in_repl(file_path)
        file_path == "(irb)" || file_path == "(pry)"
      end

      def find_proc(node, region)
        return [] unless node.is_a?(Parser::AST::Node)
        result = []
        is_match = node.type == :block && node.location.begin.line == region.begin_line
        result << node if is_match
        result += node.children.flat_map { |c| find_proc(c, region) }.reject(&:nil?)
        result
      end
    end
  end
  # require_glob 'destruct/**/*.rb'
  # frozen_string_literal: true

  require 'active_support/core_ext/object/deep_dup'
  # require_relative 'types'
  # frozen_string_literal: true

  # require_relative './monkeypatch'

  class Destruct
    # Accept any value
    Any = make_singleton("#<Any>")

    module Binder
    end

    # Bind a single value
    Var = Struct.new(:name)
    class Var
      include Binder

      def initialize(name)
        self.name = name
      end

      def inspect
        "#<Var: #{name}>"
      end
      alias_method :to_s, :inspect
    end

    # Bind zero or more values
    Splat = Struct.new(:name)
    class Splat
      include Binder

      def initialize(name)
        self.name = name
      end

      def inspect
        "#<Splat: #{name}>"
      end
      alias_method :to_s, :inspect
    end

    # hash patterns matched within the given pattern will be matched strictly,
    # i.e., the hash being matched must have the exact same key set (no extras allowed).
    Strict = Struct.new(:pat)
    class Strict
      def inspect
        "#<Strict: #{pat}>"
      end
      alias_method :to_s, :inspect
    end

    # Bind a value but continue to match a subpattern
    Let = Struct.new(:name, :pattern)
    class Let
      include Binder

      def initialize(name, pattern)
        self.name = name
        self.pattern = pattern
      end

      def inspect
        "#<Let: #{name} = #{pattern}>"
      end
      alias_method :to_s, :inspect
    end

    # A subpattern supplied by a match-time expression
    Unquote = Struct.new(:code_expr)
    class Unquote
      def inspect
        "#<Unquote: #{code_expr}>"
      end
      alias_method :to_s, :inspect
    end

    # Match an object of a particular type with particular fields
    Obj = Struct.new(:type, :fields)
    class Obj
      def initialize(type, fields={})
        unless type.is_a?(Class) || type.is_a?(Module)
          raise "Obj type must be a Class or a Module, was: #{type}"
        end
        self.type = type
        self.fields = fields
      end

      def inspect
        "#<Obj: #{type}[#{fields.map { |(k, v)| "#{k}: #{v.inspect}"}.join(", ")}]>"
      end
      alias_method :to_s, :inspect
    end

    # Bind based on the first pattern that matches
    Or = Struct.new(:patterns)
    class Or
      def initialize(*patterns)
        self.patterns = flatten(patterns)
      end

      def inspect
        "#<Or: #{patterns.map(&:inspect).join(", ")}>"
      end
      alias_method :to_s, :inspect

      private

      def flatten(ps)
        ps.inject([]) {|acc, p| p.is_a?(Or) ? acc + p.patterns : acc << p}
      end
    end
  end
  require 'stringio'
  # require_relative './compiler'
  # frozen_string_literal: true

  require "pp"
  # require_relative './rbeautify'
  # frozen_string_literal: true

  # rubocop:disable all

=begin
/***************************************************************************
 *   Copyright (C) 2008, Paul Lutus                                        *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
 ***************************************************************************/
=end

  class Destruct
    module RBeautify

      # user-customizable values

      RBeautify::TabStr = " "
      RBeautify::TabSize = 2

      # indent regexp tests

      IndentExp = [
        /^module\b/,
        /^class\b/,
        /^if\b/,
        /(=\s*|^)until\b/,
        /(=\s*|^)for\b/,
        /^unless\b/,
        /(=\s*|^)while\b/,
        /(=\s*|^)begin\b/,
        /(^| )case\b/,
        /\bthen\b/,
        /^rescue\b/,
        /^def\b/,
        /\bdo\b/,
        /^else\b/,
        /^elsif\b/,
        /^ensure\b/,
        /\bwhen\b/,
        /\{[^\}]*$/,
        /\[[^\]]*$/
      ]

      # outdent regexp tests

      OutdentExp = [
        /^rescue\b/,
        /^ensure\b/,
        /^elsif\b/,
        /^end\b/,
        /^else\b/,
        /\bwhen\b/,
        /^[^\{]*\}/,
        /^[^\[]*\]/
      ]

      def RBeautify.rb_make_tab(tab)
        return (tab < 0)?"":TabStr * TabSize * tab
      end

      def RBeautify.rb_add_line(line,tab)
        line.strip!
        line = rb_make_tab(tab) + line if line.length > 0
        return line
      end

      def RBeautify.beautify_string(source, path = "")
        comment_block = false
        in_here_doc = false
        here_doc_term = ""
        program_end = false
        multiLine_array = []
        multiLine_str = ""
        tab = 0
        output = []
        source.each do |line|
          line.chomp!
          if(!program_end)
            # detect program end mark
            if(line =~ /^__END__$/)
              program_end = true
            else
              # combine continuing lines
              if(!(line =~ /^\s*#/) && line =~ /[^\\]\\\s*$/)
                multiLine_array.push line
                multiLine_str += line.sub(/^(.*)\\\s*$/,"\\1")
                next
              end

              # add final line
              if(multiLine_str.length > 0)
                multiLine_array.push line
                multiLine_str += line.sub(/^(.*)\\\s*$/,"\\1")
              end

              tline = ((multiLine_str.length > 0)?multiLine_str:line).strip
              if(tline =~ /^=begin/)
                comment_block = true
              end
              if(in_here_doc)
                in_here_doc = false if tline =~ %r{\s*#{here_doc_term}\s*}
              else # not in here_doc
                if tline =~ %r{=\s*<<}
                  here_doc_term = tline.sub(%r{.*=\s*<<-?\s*([_|\w]+).*},"\\1")
                  in_here_doc = here_doc_term.size > 0
                end
              end
            end
          end
          if(comment_block || program_end || in_here_doc)
            # add the line unchanged
            output << line
          else
            comment_line = (tline =~ /^#/)
            if(!comment_line)
              # throw out sequences that will
              # only sow confusion
              while tline.gsub!(/\{[^\{]*?\}/,"")
              end
              while tline.gsub!(/\[[^\[]*?\]/,"")
              end
              while tline.gsub!(/'.*?'/,"")
              end
              while tline.gsub!(/".*?"/,"")
              end
              while tline.gsub!(/\`.*?\`/,"")
              end
              while tline.gsub!(/\([^\(]*?\)/,"")
              end
              while tline.gsub!(/\/.*?\//,"")
              end
              while tline.gsub!(/%r(.).*?\1/,"")
              end
              # delete end-of-line comments
              tline.sub!(/#[^\"]+$/,"")
              # convert quotes
              tline.gsub!(/\\\"/,"'")
              OutdentExp.each do |re|
                if(tline =~ re)
                  tab -= 1
                  break
                end
              end
            end
            if (multiLine_array.length > 0)
              multiLine_array.each do |ml|
                output << rb_add_line(ml,tab)
              end
              multiLine_array.clear
              multiLine_str = ""
            else
              output << rb_add_line(line,tab)
            end
            if(!comment_line)
              IndentExp.each do |re|
                if(tline =~ re && !(tline =~ /\s+end\s*$/))
                  tab += 1
                  break
                end
              end
            end
          end
          if(tline =~ /^=end/)
            comment_block = false
          end
        end
        error = (tab != 0)
        STDERR.puts "Error: indent/outdent mismatch: #{tab}." if error
        return output.join("\n") + "\n",error
      end # beautify_string

      def RBeautify.beautify_file(path)
        error = false
        if(path == '-') # stdin source
          source = STDIN.read
          dest,error = beautify_string(source,"stdin")
          print dest
        else # named file source
          source = File.read(path)
          dest,error = beautify_string(source,path)
          if(source != dest)
            # make a backup copy
            File.open(path + "~","w") { |f| f.write(source) }
            # overwrite the original
            File.open(path,"w") { |f| f.write(dest) }
          end
        end
        return error
      end # beautify_file

      def RBeautify.main
        error = false
        if(!ARGV[0])
          STDERR.puts "usage: Ruby filenames or \"-\" for stdin."
          exit 0
        end
        ARGV.each do |path|
          error = (beautify_file(path))?true:error
        end
        error = (error)?1:0
        exit error
      end # main
    end # module RBeautify
  end

  # if launched as a standalone program, not loaded as a module
  if __FILE__ == $0
    RBeautify.main
  end
  # rubocop:enable all
  # require_relative './code_gen'
  # frozen_string_literal: true

  require 'stringio'

  class Destruct
    # Helper methods for generating code
    module CodeGen
      GeneratedCode = Struct.new(:proc, :code, :filename)
      class GeneratedCode
        def inspect
          "#<GeneratedCode: #{filename}>"
        end

        def show
          CodeGen.show_code(self)
        end
      end

      def emitted
        @emitted ||= StringIO.new
      end

      def emit(str)
        emitted << str
        emitted << "\n"
      end

      def generate(filename='', line=1)
      code = <<~CODE
        # frozen_string_literal: true
        lambda do |_code, _filename, _refs#{ref_args}|
          #{emitted.string}
        end
      CODE
      code = beautify_ruby(code)
      begin
        result = eval(code, nil, filename, line - 2).call(code, filename, refs, *refs.values)
        gc = GeneratedCode.new(result, code, filename)
        show_code(gc) if Destruct.show_code
        gc
      rescue SyntaxError
        show_code(code, filename, refs, fancy: false, include_vm: false)
        raise
      end
    end

    def self.quick_gen(filename='', line=1, &block)
      Class.new do
        include CodeGen
        define_method(:initialize) do
          instance_exec(&block)
        end
      end.new.generate(filename, line)
    end

    def show_code_on_error
      emit_begin do
        yield
      end.rescue do
        emit "Destruct::CodeGen.show_code(_code, _filename, _refs, fancy: false)"
        emit "raise"
      end.end
    end

    def emit_begin
      emit "begin"
      yield
      Begin.new(self)
    end

    def emit_lambda(*args, &emit_body)
      emit "lambda do |#{args.join(", ")}|"
      emit_body.call
      emit "end"
    end

    def emit_if(cond)
      emit "if #{cond}"
      yield
      If.new(self)
    end

    class If
      def initialize(parent)
        @parent = parent
      end

      def elsif(cond)
        @parent.instance_exec do
          emit "elsif #{cond}"
          yield
        end
        self
      end

      def else
        @parent.instance_exec do
          emit "else"
          yield
          emit "end"
        end
        self
      end

      def end
        @parent.instance_exec do
          emit "end"
        end
      end
    end

    class Begin
      def initialize(parent)
        @parent = parent
      end

      def rescue(type_clause="")
        @parent.instance_exec do
          emit "rescue #{type_clause}"
          yield
        end
        self
      end

      def end
        @parent.instance_exec do
          emit "end"
        end
      end
    end

    private def ref_args
      return "" if refs.none?
      width = refs.keys.map(&:to_s).map(&:size).max
      ", \n#{refs.map { |k, v| "#{k.to_s.ljust(width)}, # #{v.inspect}" }.join("\n")}\n"
    end

    def beautify_ruby(code)
      Destruct::RBeautify.beautify_string(code.split("\n").reject { |line| line.strip == '' }).first
    end

    def refs
      @refs ||= {}
    end

    def reverse_refs
      @reverse_refs ||= {}
    end

    # obtain a runtime reference to a compile-time value
    def get_ref(value, id=nil)
      reverse_refs.fetch(value) do
        if id
          raise "ref #{id} is already bound" if refs.keys.include?(id)
        else
          id = get_temp
        end
        refs[id] = value
        reverse_refs[value] = id
        id
      end
    end

    # obtain a unique temporary identifier
    def get_temp(prefix="t")
      @temp_num ||= 0
      "_#{prefix}#{@temp_num += 1}"
    end

    module_function

    def show_code(code, filename="", refs=(self.respond_to?(:refs) ? self.refs : {}),
                  fancy: false, include_vm: false, seen: [])
      if code.is_a?(GeneratedCode)
        gc = code
        code = gc.code
        filename = gc.filename
      end
      return if seen.include?(code)
      seen << code
      refs.values.each do |v|
        if v.is_a?(CompiledPattern)
          show_code(v.generated_code, seen: seen)
        elsif v.is_a?(GeneratedCode)
          show_code(v, seen: seen)
        end
      end
      lines = number_lines(code, -2) # -2 to line up with stack traces
      if fancy
        lines = lines
                    .reject { |line| line =~ /^\s*\d+\s*puts/ }
                    .map do |line|
          if line !~ /, #|_code|_refs/
            refs.each do |k, v|
              line = line.gsub(/#{k}(?!\d+)/, v.inspect)
            end
          end
          line
        end
      end
      puts
      puts filename
      puts lines
      if include_vm
        pp RubyVM::InstructionSequence.compile(code).to_a
      end
    end

    def number_lines(code, offset=0)
      code.split("\n").each_with_index.map do |line, n|
        "#{(n + 1 + offset).to_s.rjust(3)} #{line}"
      end
    end
  end
end
require "set"

class Destruct
  class Compiler
    include CodeGen

    class << self
      def compile(pat)
        if pat.is_a?(CompiledPattern)
          pat
        else
          compiled_patterns.fetch(pat) do # TODO: consider caching by object_id
            compiled_patterns[pat] = begin
              cp = Compiler.new.compile(pat)
              on_compile_handlers.each { |h| h.(pat) }
              cp
            end
          end
        end
      end

      def compiled_patterns
        Thread.current[:__boot1_destruct_compiled_patterns__] ||= {}
      end

      def match(pat, x)
        compile(pat).match(x)
      end

      def on_compile(&block)
        on_compile_handlers << block
      end

      private def on_compile_handlers
        @on_compile_handlers ||= []
      end
    end

    Frame = Struct.new(:pat, :x, :env, :parent, :type)

    def initialize
      @known_real_envs ||= Set.new
    end

    def compile(pat)
      @var_counts = var_counts(pat)
      @var_names = @var_counts.keys
      if @var_names.any?
        get_ref(Destruct::Env.new_class(*@var_names).method(:new), "_make_env")
      end

      x = get_temp("x")
      env = get_temp("env")
      emit_lambda(x, "_binding") do
        show_code_on_error do
          emit "#{env} = true"
          match(Frame.new(pat, x, env))
          emit env
        end
      end
      g = generate("Matcher for: #{pat.inspect.gsub(/\s+/, " ")}")
      CompiledPattern.new(pat, g, @var_names)
    end

    def var_counts(pat)
      find_var_names_non_uniq(pat).group_by(&:itself).map { |k, vs| [k, vs.size] }.to_h
    end

    def find_var_names_non_uniq(pat)
      if pat.is_a?(Obj)
        pat.fields.values.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Or)
        @has_or = true
        pat.patterns.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Let)
        [pat.name, *find_var_names_non_uniq(pat.pattern)]
      elsif pat.is_a?(Binder)
        [pat.name]
      elsif pat.is_a?(Hash)
        pat.values.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Array)
        pat.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Regexp)
        pat.named_captures.keys.map(&:to_sym)
      elsif pat.is_a?(Strict)
        find_var_names_non_uniq(pat.pat)
      else
        []
      end
    end

    def match(s)
      if s.pat == Any
        # do nothing
      elsif s.pat.is_a?(Obj)
        match_obj(s)
      elsif s.pat.is_a?(Or)
        match_or(s)
      elsif s.pat.is_a?(Let)
        match_let(s)
      elsif s.pat.is_a?(Var)
        match_var(s)
      elsif s.pat.is_a?(Unquote)
        match_unquote(s)
      elsif s.pat.is_a?(Hash)
        match_hash(s)
      elsif s.pat.is_a?(Array)
        match_array(s)
      elsif s.pat.is_a?(Regexp)
        match_regexp(s)
      elsif s.pat.is_a?(Strict)
        match_strict(s)
      elsif is_literal_val?(s.pat)
        match_literal(s)
      elsif
      match_other(s)
      end
    end

    def is_literal_val?(x)
      x.is_a?(Numeric) || x.is_a?(String) || x.is_a?(Symbol)
    end

    def is_literal_pat?(p)
      !(p.is_a?(Obj) ||
          p.is_a?(Or) ||
          p.is_a?(Binder) ||
          p.is_a?(Unquote) ||
          p.is_a?(Hash) ||
          p.is_a?(Array))
    end

    def pattern_order(p)
      # check the cheapest or most likely to fail first
      if is_literal_pat?(p)
        0
      elsif p.is_a?(Or) || p.is_a?(Regexp)
        2
      elsif p.is_a?(Binder)
        3
      elsif p.is_a?(Unquote)
        4
      else
        1
      end
    end

    def match_array(s)
      s.type = :array
      splat_count = s.pat.count { |p| p.is_a?(Splat) }
      if splat_count > 1
        raise "An array pattern cannot have more than one splat: #{s.pat}"
      end
      splat_index = s.pat.find_index { |p| p.is_a?(Splat) }
      is_closed = !splat_index || splat_index != s.pat.size - 1
      pre_splat_range = 0...(splat_index || s.pat.size)

      s.x = localize(nil, s.x)
      known_real_envs_before = @known_real_envs.dup
      emit_if "#{s.x}.is_a?(Array)" do
        cond = splat_index ? "#{s.x}.size >= #{s.pat.size - 1}" : "#{s.x}.size == #{s.pat.size}"
        test(s, cond) do

          pre_splat_range
              .map { |i| [s.pat[i], i] }
              .sort_by { |(item_pat, i)| [pattern_order(item_pat), i] }
              .each do |item_pat, i|
            x = localize(item_pat, "#{s.x}[#{i}]")
            match(Frame.new(item_pat, x, s.env, s))
          end

          if splat_index
            splat_range = get_temp("splat_range")
            post_splat_width = s.pat.size - splat_index - 1
            emit "#{splat_range} = #{splat_index}...(#{s.x}.size#{post_splat_width > 0 ? "- #{post_splat_width}" : ""})"
            bind(s, s.pat[splat_index], "#{s.x}[#{splat_range}]")

            post_splat_pat_range = ((splat_index + 1)...s.pat.size)
            post_splat_pat_range.each do |i|
              item_pat = s.pat[i]
              x = localize(item_pat, "#{s.x}[-#{s.pat.size - i}]")
              match(Frame.new(item_pat, x, s.env, s))
            end
          end
        end
      end.elsif "#{s.x}.is_a?(Enumerable)" do
        @known_real_envs = known_real_envs_before
        en = get_temp("en")
        done = get_temp("done")
        stopped = get_temp("stopped")
        emit "#{en} = #{s.x}.each"
        emit "#{done} = false"
        emit_begin do
          s.pat[0...(splat_index || s.pat.size)].each do |item_pat|
            x = localize(item_pat, "#{en}.next")
            match(Frame.new(item_pat, x, s.env, s))
          end

          if splat_index
            if is_closed
              splat = get_temp("splat")
              emit "#{splat} = []"
              splat_len = get_temp("splat_len")
              emit "#{splat_len} = #{s.x}.size - #{s.pat.size - 1}"
              emit "#{splat_len}.times do"
              emit "#{splat} << #{en}.next"
              emit "end"
              bind(s, s.pat[splat_index], splat)

              s.pat[(splat_index+1)...(s.pat.size)].each do |item_pat|
                x = localize(item_pat, "#{en}.next")
                match(Frame.new(item_pat, x, s.env, s))
              end
            else
              bind(s, s.pat[splat_index], "#{en}.new_from_here")
            end
          end

          emit "#{done} = true"
          emit "#{en}.next" if is_closed
        end.rescue "StopIteration" do
          emit "#{stopped} = true"
          test(s, done)
        end.end
        test(s, stopped) if is_closed
      end.else do
        test(s, "nil")
      end
    end

    def in_or(s)
      !s.nil? && (s.type == :or || in_or(s.parent))
    end

    def in_strict(s)
      !s.nil? && (s.pat.is_a?(Strict) || in_strict(s.parent))
    end

    def match_regexp(s)
      s.type = :regexp
      m = get_temp("m")
      match_env = get_temp("env")
      test(s, "#{s.x}.is_a?(String) || #{s.x}.is_a?(Symbol)") do
        emit "#{m} = #{get_ref(s.pat)}.match(#{s.x})"
        emit "#{match_env} = Destruct::Env.new(#{m}) if #{m}"
        test(s, match_env)
        merge(s, match_env, dynamic: true)
      end
    end

    def match_strict(s)
      match(Frame.new(s.pat.pat, s.x, s.env, s))
    end

    def match_literal(s)
      s.type = :literal
      test(s, "#{s.x} == #{s.pat.inspect}")
    end

    def match_other(s)
      s.type = :other
      test(s, "#{s.x} == #{get_ref(s.pat)}")
    end

    def test(s, cond)
      # emit "puts \"line #{emitted_line_count + 8}: \#{#{cond.inspect}}\""
      emit "puts \"test: \#{#{cond.inspect}}\"" if $show_tests
      if in_or(s)
        emit "#{s.env} = (#{cond}) ? #{s.env} : nil if #{s.env}"
        if block_given?
          emit_if s.env do
            yield
          end.end
        end
      elsif cond == "nil" || cond == "false"
        emit "return nil"
      else
        emit "#{cond} or return nil"
        yield if block_given?
      end
    end

    def match_var(s)
      s.type = :var
      test(s, "#{s.x} != #{nothing_ref}")
      bind(s, s.pat, s.x)
    end

    def match_unquote(s)
      temp_env = get_temp("env")
      emit "raise 'binding must be provided' if _binding.nil?"
      emit "#{temp_env} = Destruct.match((_binding.respond_to?(:call) ? _binding.call : _binding).eval('#{s.pat.code_expr}'), #{s.x}, _binding)"
      test(s, temp_env)
      merge(s, temp_env, dynamic: true)
    end

    def match_let(s)
      s.type = :let
      match(Frame.new(s.pat.pattern, s.x, s.env, s))
      bind(s, s.pat, s.x)
    end

    def bind(s, var, val, val_could_be_unbound_sentinel=false)
      var_name = var.is_a?(Binder) ? var.name : var

      # emit "# bind #{var_name}"
      proposed_val =
          if val_could_be_unbound_sentinel
            # we'll want this in a local because the additional `if` clause below will need the value a second time.
            pv = get_temp("proposed_val")
            emit "#{pv} = #{val}"
            pv
          else
            val
          end

      do_it = proc do
        unless @known_real_envs.include?(s.env)
          # no need to ensure the env is real (i.e., an Env, not `true`) if it's already been ensured
          emit "#{s.env} = _make_env.() if #{s.env} == true"
          @known_real_envs.add(s.env) unless in_or(s)
        end
        current_val = "#{s.env}.#{var_name}"
        if @var_counts[var_name] > 1
          # if the pattern binds the var in two places, we'll have to check if it's already bound
          emit_if "#{current_val} == :__boot1_unbound__" do
            emit "#{s.env}.#{var_name} = #{proposed_val}"
          end.elsif "#{current_val} != #{proposed_val}" do
            if in_or(s)
              emit "#{s.env} = nil"
            else
              test(s, "nil")
            end
          end.end
        else
          # otherwise, this is the only place we'll attempt to bind this var, so just do it
          emit "#{current_val} = #{proposed_val}"
        end
      end

      if in_or(s)
        emit_if("#{s.env}", &do_it).end
      elsif val_could_be_unbound_sentinel
        emit_if("#{s.env} && #{proposed_val} != :__boot1_unbound__", &do_it).end
      else
        do_it.()
      end

      test(s, "#{s.env}") if in_or(s)
    end

    def match_obj(s)
      s.type = :obj
      match_hash_or_obj(s, get_ref(s.pat.type), s.pat.fields, proc { |field_name| "#{s.x}.#{field_name}" })
    end

    def match_hash(s)
      s.type = :hash
      match_hash_or_obj(s, "Hash", s.pat, proc { |field_name| "#{s.x}.fetch(#{field_name.inspect}, #{nothing_ref})" },
                        "#{s.x}.keys.sort == #{get_ref(s.pat.keys.sort)}")
    end

    def nothing_ref
      get_ref(Destruct::NOTHING)
    end

    def match_hash_or_obj(s, type_str, pairs, make_x_sub, strict_test=nil)
      test(s, "#{s.x}.is_a?(#{type_str})") do
        keep_matching = proc do
          pairs
              .sort_by { |(_, field_pat)| pattern_order(field_pat) }
              .each do |field_name, field_pat|
            x = localize(field_pat, make_x_sub.(field_name), field_name)
            match(Frame.new(field_pat, x, s.env, s))
          end
        end

        if in_strict(s) && strict_test
          test(s, strict_test) { keep_matching.call }
        else
          keep_matching.call
        end
      end
    end

    def multi?(pat)
      pat.is_a?(Or) ||
          (pat.is_a?(Array) && pat.size > 1) ||
          pat.is_a?(Obj) && pat.fields.any?
    end

    def match_or(s)
      s.type = :or
      closers = []
      or_env = get_temp("env")
      emit "#{or_env} = true"
      s.pat.patterns.each_with_index do |alt, i|
        match(Frame.new(alt, s.x, or_env, s))
        if i < s.pat.patterns.size - 1
          emit "unless #{or_env}"
          closers << proc { emit "end" }
          emit "#{or_env} = true"
        end
      end
      closers.each(&:call)
      merge(s, or_env)
      emit "#{s.env} or return nil" if !in_or(s.parent)
    end

    def merge(s, other_env, dynamic: false)
      @known_real_envs.include?(s.env)

      emit_if("#{s.env}.nil? || #{other_env}.nil?") do
        emit "#{s.env} = nil"
      end.elsif("#{s.env} == true") do
        emit "#{s.env} = #{other_env}"
      end.elsif("#{other_env} != true") do
        if dynamic
          emit "#{other_env}.env_each do |k, v|"
          emit_if("#{s.env}[k] == :__boot1_unbound__") do
            emit "#{s.env}[k] = v"
          end.elsif("#{s.env}[k] != v") do
            if in_or(s)
              emit "#{s.env} = nil"
            else
              test(s, "nil")
            end
          end.end
          emit "end"
        else
          @var_names.each do |var_name|
            bind(s, var_name, "#{other_env}.#{var_name}", true)
          end
        end
      end.end
    end

    private

    def localize(pat, x, prefix="t")
      prefix = prefix.to_s.gsub(/[^\w\d_]/, '')
      if (pat.nil? && x =~ /\.\[\]/) || multi?(pat) || (pat.is_a?(Binder) && x =~ /\.fetch|\.next/)
        t = get_temp(prefix)
        emit "#{t} = #{x}"
        x = t
      end
      x
    end
  end

  class Pattern
    attr_reader :pat

    def initialize(pat)
      @pat = pat
    end

    def to_s
      "#<Pattern #{pat}>"
    end

    alias_method :inspect, :to_s

    def match(x, binding=nil)
      Compiler.compile(pat).match(x, binding)
    end
  end

  class CompiledPattern
    attr_reader :pat, :generated_code, :var_names

    def initialize(pat, generated_code, var_names)
      @pat = pat
      @generated_code = generated_code
      @var_names = var_names
    end

    def match(x, binding=nil)
      @generated_code.proc.(x, binding)
    end

    def show_code
      generated_code.show
    end
  end
end

module Enumerable
  def rest
    result = []
    while true
      result << self.next
    end
  rescue StopIteration
    result
  end

  def new_from_here
    orig = self
    WrappedEnumerator.new(orig) do |y|
      while true
        y << orig.next
      end
    end
  end
end

class WrappedEnumerator < Enumerator
  def initialize(inner, &block)
    super(&block)
    @inner = inner
  end

  def new_from_here
    orig = @inner
    WrappedEnumerator.new(orig) do |y|
      while true
        y << orig.next
      end
    end
  end
end

class Destruct
  class Transformer
    DEBUG = false
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
        if DEBUG || Destruct.show_transformations
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
            next unless validate_constraints(args, rule.constraints)
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

    def validate_constraints(args, constraints)
      constraints.each_pair do |var, const|
        return false unless validate_constraint(args[var], const)
      end
    end

    def validate_constraint(x, c)
      if c.is_a?(Module)
        x.is_a?(c)
      elsif c.is_a?(Array) && c.size == 1
        return false unless x.is_a?(Array) || x.is_a?(Hash)
        vs = x.is_a?(Array) ? x : x.values
        vs.all? { |v| validate_constraint(v, c[0]) }
      elsif c.is_a?(Array)
        c.any? { |c| validate_constraint(x, c) }
      elsif c.respond_to?(:call)
        c.(x)
      end
    end

    def apply_template(x, rule, args=[], kws={})
      if proc_has_kw(rule.template, :binding)
        if @binding.nil?
          raise 'binding must be provided'
        end
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
# require_glob 'destruct/**/*.rb'
# require_relative './rule_sets/helpers'
class Destruct
  module RuleSets
    module Helpers
      def n(type, children=[])
        Obj.new(Parser::AST::Node, type: type, children: children)
      end

      def v(name)
        Var.new(name)
      end

      def s(name)
        Splat.new(name)
      end

      def any(*alt_patterns)
        if alt_patterns.none?
          Any
        else
          Or.new(*alt_patterns)
        end
      end

      def let(name, pat)
        Let.new(name, pat)
      end
    end
  end
end

class Destruct
  module RuleSet
    DEBUG = false

    def rules
      @rules ||= []
    end

    def self.included(base)
      base.extend(ClassMethods)
      base.include(RuleSets::Helpers)
    end

    module ClassMethods
      def transform(x=NOTHING, binding: nil, **hash_arg, &x_proc)
        instance.transform(x, binding: binding, **hash_arg, &x_proc)
      end

      def instance
        @instance ||= new
      end
    end

    def transform(x=NOTHING, binding: nil, **hash_arg, &x_proc)
      if x != NOTHING && x_proc
        raise "Pass either x or a block but not both"
      end
      x = x == NOTHING && x_proc.nil? ? hash_arg : x # ruby interprets a hash arg as keywords rather than a value for x
      x = x != NOTHING ? x : x_proc
      x = x.is_a?(Proc) ? ExprCache.get(x) : x
      binding ||= x_proc&.binding
      result = Transformer.transform(x == NOTHING ? x_proc : x, self, binding)
      self.validate(result) if self.respond_to?(:validate)
      result
    end

    # @param pat_or_proc [Object] One of:
    #   an AST-matching destruct pattern,
    #   a proc containing syntax for a meta rule set to convert into an AST-matching destruct pattern, or
    #   a class.
    # The block should take keyword parameters that match the names of variables bound by the pattern.
    # These values are fully transformed before being passed to the block. To obtain the untransformed
    # syntax of variable "x", the block may request parameter "raw_x" instead. The block may also request
    # the special parameters "binding" and/or "transform". "binding" is the Binding within which the pattern
    # is being evaluated. "transform" is the transformation method, which allows the block to insert itself
    # into the recursive transformation process.
    def add_rule(pat_or_proc, constraints={}, &translate_block)
      if pat_or_proc.is_a?(Proc)
        node = ExprCache.get(pat_or_proc)
        pat = (@meta_rule_set || RuleSets::AstToPattern).transform(node)
        rules << Transformer::Rule.new(pat, translate_block, constraints)
      else
        rules << Transformer::Rule.new(pat_or_proc, translate_block, constraints)
      end
    end

    private

    def meta_rule_set(rule_set)
      @meta_rule_set = rule_set
    end

    def add_rule_set(rule_set)
      if rule_set.is_a?(Class)
        rule_set = rule_set.instance
      end
      rule_set.rules.each { |r| rules << r }
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'stringio'

class Destruct
  # Holds the variables bound during pattern matching. For many patterns, the variable
  # names are known at compilation time, so Env.new_class is used to create a derived
  # Env that can hold exactly those variables. If a pattern contains a Regex, Or, or
  # Unquote, then the variables bound are generally not known until the pattern is matched
  # against a particular object at run time. The @extras hash is used to bind these variables.
  class Env
    NIL = Object.new
    UNBOUND = :__boot1_unbound__

    def method_missing(name, *args, &block)
      name_str = name.to_s
      if name_str.end_with?('=')
        @extras ||= {}
        @extras[name_str[0..-2].to_sym] = args[0]
      else
        if @extras.nil?
          Destruct::Env::UNBOUND
        else
          @extras.fetch(name) { Destruct::Env::UNBOUND }
        end
      end
    end

    def initialize(regexp_match_data=nil)
      if regexp_match_data
        @extras = regexp_match_data.names.map { |n| [n.to_sym, regexp_match_data[n]] }.to_h
      end
    end

    def env_each
      if @extras
        @extras.each_pair { |k, v| yield(k, v) }
      end
    end

    def env_keys
      result = []
      env_each { |k, _| result.push(k) }
      result
    end

    # deprecated
    def [](var_name)
      self.send(var_name)
    end

    # only for dynamic binding
    def []=(var_name, value)
      self.send(:"#{var_name}=", value)
    end

    def to_s
      kv_strs = []
      env_each do |k, v|
        kv_strs << "#{k}=#{v.inspect}"
      end
      "#<Env: #{kv_strs.join(", ")}>"
    end
    alias_method :inspect, :to_s

    def self.new_class(*var_names)
      Class.new(Env) do
        attr_accessor(*var_names)
        eval <<~CODE
          def initialize
            #{var_names.map { |v| "@#{v} = :__boot1_unbound__" }.join("\n")}
          end

          def env_each
            #{var_names.map { |v| "yield(#{v.inspect}, @#{v})" }.join("\n")}
            if @extras
              @extras.each_pair { |k, v| yield(k, v) }
            end
          end

          def self.name; "Destruct::Env"; end
        CODE
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'unparser'

class Destruct
  include CodeGen

  NOTHING = make_singleton("#<NOTHING>")

  class << self
    attr_accessor :show_code, :show_transformations

    def instance
      Thread.current[:__boot1_destruct_cache_instance__] ||= Destruct.new
    end

    def get_compiled(p, get_binding=nil)
      instance.get_compiled(p, get_binding)
    end

    def destruct(value, &block)
      instance.destruct(value, &block)
    end
  end

  def self.match(pat, x, binding=nil)
    if pat.is_a?(Proc)
      pat = RuleSets::StandardPattern.transform(binding: binding, &pat)
    end
    Compiler.compile(pat).match(x, binding)
  end

  def initialize(rule_set=RuleSets::StandardPattern)
    @rule_set = rule_set
  end

  def get_compiled(p, get_binding)
    @cpats_by_proc_id ||= {}
    key = p.source_location_id
    @cpats_by_proc_id.fetch(key) do
      binding = get_binding.call # obtaining the proc binding allocates heap, so only do so when necessary
      @cpats_by_proc_id[key] = Compiler.compile(@rule_set.transform(binding: binding, &p))
    end
  end

  def destruct(value, &block)
    context = contexts.pop || Context.new
    begin
      cached_binding = nil
      context.init(self, value) { cached_binding ||= block.binding }
      context.instance_exec(&block)
    ensure
      contexts.push(context)
    end
  end

  def contexts
    # Avoid allocations by keeping a stack for each thread. Maximum stack depth of 100 should be plenty.
    Thread.current[:__boot1_destruct_contexts__] ||= [] # Array.new(100) { Context.new }
  end

  class Context
    # BE CAREFUL TO MAKE SURE THAT init() clears all instance vars

    def init(parent, value, &get_outer_binding)
      @parent = parent
      @value = value
      @get_outer_binding = get_outer_binding
      @env = nil
      @outer_binding = nil
      @outer_self = nil
    end

    def match(pat=nil, &pat_proc)
      cpat = pat ? Compiler.compile(pat) : @parent.get_compiled(pat_proc, @get_outer_binding)
      @env = cpat.match(@value, @get_outer_binding)
    end

    def outer_binding
      @outer_binding ||= @get_outer_binding.call
    end

    def outer_self
      @outer_self ||= outer_binding.eval("self")
    end

    def method_missing(method, *args, &block)
      bound_value = @env.is_a?(Env) ? @env[method] : Env::UNBOUND
      if bound_value != Env::UNBOUND
        bound_value
      elsif outer_self
        outer_self.send method, *args, &block
      else
        super
      end
    end
  end
end

def destruct(value, &block)
  Destruct.destruct(value, &block)
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

# require_relative './ruby'
# frozen_string_literal: true

# require_relative './unpack_enumerables'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class UnpackEnumerables
      include RuleSet
      include Helpers

      def initialize
        add_rule(Array) { |a, transform:| a.map { |v| transform.(v) } }
        add_rule(Hash) { |h, transform:| h.map { |k, v| [transform.(k), transform.(v)] }.to_h }
      end

      class VarRef
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_s
          "#<VarRef: #{name}>"
        end
        alias_method :inspect, :to_s
      end

      class ConstRef
        attr_reader :fqn

        def initialize(fqn)
          @fqn = fqn
        end

        def to_s
          "#<ConstRef: #{fqn}>"
        end
        alias_method :inspect, :to_s
      end
    end
  end
end

class Object
  def transformer_eql?(other)
    self == other
  end
end

class Destruct
  module RuleSets
    class Ruby
      include RuleSet
      include Helpers

      def initialize
        add_rule(n(any(:int, :sym, :float, :str), [v(:value)])) { |value:| value }
        add_rule(n(:nil, [])) { nil }
        add_rule(n(:true, [])) { true }
        add_rule(n(:false, [])) { false }
        add_rule(n(:array, v(:items))) { |items:| items }
        add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
        add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
        add_rule(n(:lvar, [v(:name)])) { |name:| VarRef.new(name) }
        add_rule(n(:send, [nil, v(:name)])) { |name:| VarRef.new(name) }
        add_rule(n(:const, [v(:parent), v(:name)]), parent: [ConstRef, NilClass]) do |parent:, name:|
          ConstRef.new([parent&.fqn, name].compact.join("::"))
        end
        add_rule(n(:cbase)) { ConstRef.new("") }
        add_rule(let(:matched, n(:regexp, any))) { |matched:| eval(unparse(matched)) }
        add_rule_set(UnpackEnumerables)
      end

      class VarRef
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_s
          "#<VarRef: #{name}>"
        end
        alias_method :inspect, :to_s
      end

      class ConstRef
        attr_reader :fqn

        def initialize(fqn)
          @fqn = fqn
        end

        def to_s
          "#<ConstRef: #{fqn}>"
        end
        alias_method :inspect, :to_s
      end

      def m(type, *children)
        Parser::AST::Node.new(type, children)
      end
    end
  end
end
# require_relative './pattern_validator'
class Destruct
  module RuleSets
    # Used to verify a transformer hasn't left any untransformed syntax around
    class PatternValidator
      class << self
        def validate(x)
          if x.is_a?(Or)
            x.patterns.each { |v| validate(v) }
          elsif x.is_a?(Obj)
            x.fields.values.each { |v| validate(v) }
          elsif x.is_a?(Let)
            validate(x.pattern)
          elsif x.is_a?(Array)
            x.each { |v| validate(v) }
          elsif x.is_a?(Strict)
            validate(x.pat)
          elsif x.is_a?(Hash)
            unless x.keys.all? { |k| k.is_a?(Symbol) }
              raise "Invalid pattern: #{x}"
            end
            x.values.each { |v| validate(v) }
          elsif !(x.is_a?(Binder) || x.is_a?(Unquote) || x.is_a?(Module) || x == Any || x.primitive?)
            raise "Invalid pattern: #{x}"
          end
        end
      end
    end
  end
end

class Destruct
  module RuleSets
    class PatternBase
      include RuleSet

      def initialize
        add_rule(Ruby::VarRef) { |ref| Var.new(ref.name) }
        add_rule(Ruby::ConstRef) { |ref, binding:| binding.eval(ref.fqn) }
        add_rule_set(Ruby)
      end

      def validate(x)
        PatternValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'ast'

class Destruct
  module RuleSets
    class UnpackAst
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const lvar].freeze

      def initialize
        add_rule(Parser::AST::Node) do |n, transform:|
          raise Transformer::NotApplicable if ATOMIC_TYPES.include?(n.type)
          n.updated(nil, n.children.map(&transform))
        end
      end

      def m(type, *children)
        Parser::AST::Node.new(type, children)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class RubyInverse
      include RuleSet

      def initialize
        add_rule(Integer) { |value| n(:int, value) }
        add_rule(Symbol) { |value| n(:sym, value) }
        add_rule(Float) { |value| n(:float, value) }
        add_rule(String) { |value| n(:str, value) }
        add_rule(nil) { n(:nil) }
        add_rule(true) { n(:true) }
        add_rule(false) { n(:false) }
        add_rule(Array) { |items| n(:array, *items) }
        add_rule(Hash) { |h, transform:| n(:hash, *h.map { |k, v| n(:pair, transform.(k), transform.(v)) }) }
        add_rule(Module) { |m| m.name.split("::").map(&:to_sym).reduce(n(:cbase)) { |base, name| n(:const, base, name) } }
        add_rule_set(UnpackAst)
      end

      def n(type, *children)
        ::Parser::AST::Node.new(type, children)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
class Destruct
  module RuleSets
    class AstValidator
      class << self
        def validate(x)
          if x.is_a?(Parser::AST::Node)
            if !x.type.is_a?(Symbol)
              raise "Invalid pattern: #{x}"
            end
            x.children.each { |v| validate(v) }
          elsif !x.primitive?
            raise "Invalid pattern: #{x}"
          end
        end
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class Quote
      include RuleSet

      def initialize
        add_rule(->{ !expr }) do |raw_expr:, binding:|
          value = binding.eval(unparse(raw_expr))
          if value.is_a?(Parser::AST::Node)
            value
          else
            PatternInverse.transform(value)
          end
        end
        add_rule_set(UnpackAst)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class StandardPattern
      include RuleSet

      def initialize
        meta_rule_set AstToPattern
        add_rule(->{ strict(pat) }) { |pat:| Strict.new(pat) }
        add_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
        add_rule(->{ !expr }) { |expr:| Unquote.new(Transformer.unparse(expr)) }
        add_rule(->{ name <= pat }, name: Var) { |name:, pat:| Let.new(name.name, pat) }
        add_rule(-> { a | b }) { |a:, b:| Or.new(a, b) }
        add_rule(->{ klass[*field_pats] }, klass: [Class, Module], field_pats: [Var]) do |klass:, field_pats:|
          Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
        end
        add_rule(->{ klass[field_pats] }, klass: [Class, Module], field_pats: Hash) do |klass:, field_pats:|
          Obj.new(klass, field_pats)
        end
        add_rule(->{ is_a?(klass) }, klass: [Class, Module]) { |klass:| Obj.new(klass) }
        add_rule(->{ v }, v: [Var, Ruby::VarRef]) do |v:|
          raise Transformer::NotApplicable unless v.name == :_
          Any
        end
        add_rule_set(PatternBase)
      end

      def validate(x)
        PatternValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'ast'

class Destruct
  module RuleSets
    class AstToPattern
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const lvar].freeze

      def initialize
        mvar = n(:send, [nil, v(:name)])
        lvar = n(:lvar, [v(:name)])
        add_rule(any(mvar, lvar)) do |name:|
          Var.new(name)
        end
        add_rule(n(:splat, [any(mvar, lvar)])) do |name:|
          Splat.new(name)
        end
        add_rule(Parser::AST::Node) do |node, transform:|
          n(node.type, node.children.map { |c| transform.(c) })
        end
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class PatternInverse
      include RuleSet

      def initialize
        add_rule(Var) { |var| n(:lvar, var.name) }
        add_rule_set(RubyInverse)
      end

      def n(type, *children)
        ::Parser::AST::Node.new(type, children)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
require_relative '/home/pwinton/git/destruct/lib/destruct_ext.so'
end
$boot_code ||= {}
$boot_code['boot1'] = <<'BOOT_CODE'
require 'ast'

def make_singleton(inspect_str)
  obj = Object.new
  obj.define_singleton_method(:to_s) { inspect_str }
  obj.define_singleton_method(:inspect) { inspect_str }
  obj
end

class Object
  def primitive?
    is_a?(Numeric) || is_a?(String) || is_a?(Symbol) || is_a?(Regexp) || self == true || self == false || self == nil
  end
end

module Parser
  module AST
    class Node < ::AST::Node
      def to_s1
        to_s.gsub(/\s+/, " ")
      end
    end
  end
end

module Boot1
  # frozen_string_literal: true

  def require_glob(relative_path_glob)
    dir = File.dirname(caller[0].split(':')[0])
    Dir[File.join(dir, relative_path_glob)].sort.each { |file| require file }
  end

  # require_glob 'destruct/**/*.rb'
  # frozen_string_literal: true

  require 'parser/current'
  require 'unparser'

  class Destruct
    # Obtains the AST node for a given proc
    class ExprCache
      class << self
        def instance
          Thread.current[:__boot1_syntax_cache_instance__] ||= ExprCache.new
        end

        def get(p, &k)
          instance.get(p, &k)
        end
      end

      Region = Struct.new(:path, :begin_line, :begin_col, :end_line, :end_col)

      def initialize
        @asts_by_file = {}
        @exprs_by_proc = {}
      end

      # Obtains the AST node for a given proc. The node is found by using
      # Proc#source_location to reparse the source file and find the proc's node
      # on the appropriate line. If there are multiple procs on the same line,
      # procs and lambdas are preferred over blocks, and the first is returned.
      # If try_to_use is provided, candidate nodes are passed to the block for
      # evaluation. If the node is unacceptable, the block is expected to raise
      # InvalidPattern. The first acceptable block is returned.
      # If the proc was entered at the repl, we attempt to find it in the repl
      # history.
      # TODO: Use Region.begin_col to disambiguate. It's not straightforward:
      # Ruby's parser sometimes disagrees with the parser gem. The relative
      # order of multiple procs on the same line should be identical though.
      def get(p, &try_to_use)
        cache_key = p.source_location_id
        sexp = @exprs_by_proc[cache_key]
        return sexp if sexp

        ast, region = get_ast(Region.new(*p.source_region))
        candidate_nodes = find_proc(ast, region)
        # prefer lambdas and procs over blocks
        candidate_nodes = candidate_nodes.sort_by do |n|
          n.children[0].type == :send && (n.children[0].children[1] == :lambda ||
          n.children[0].children[1] == :proc) ? 0 : 1
        end.map { |n| n.children[2] }

        if !try_to_use
          @exprs_by_proc[cache_key] =
          if candidate_nodes.size > 1
            candidate_nodes.reject { |n| contains_block?(n) }.first # hack to deal with more than one per line
          else
            candidate_nodes.first
          end
        else
          tried_candidates = candidate_nodes.map do |n|
            begin
              try_to_use.(n)
            rescue InvalidPattern => e
              e
            end
          end
          first_good_idx = tried_candidates.find_index { |x| !x.is_a?(InvalidPattern) }
          if first_good_idx
            @exprs_by_proc[cache_key] = candidate_nodes[first_good_idx]
            tried_candidates[first_good_idx]
          else
            raise InvalidPattern.new(tried_candidates.last.pattern, Unparser.unparse(candidate_nodes.last))
          end
        end
      end

      private

      def contains_block?(node)
        if !node.is_a?(Parser::AST::Node)
          false
        elsif node.type == :block
          true
        else
          node.children.any? { |c| contains_block?(c) }
        end
      end

      def get_ast(region)
        if in_repl(region.path)
          start_offset = -1
          old_stderr = $stderr
          begin
            $stderr = File.open(IO::NULL, "w") # silence parse diagnostics
            code = Readline::HISTORY.to_a[start_offset..-1].join("\n")
            [Parser::CurrentRuby.parse(code), Region.new(region.path, 1, 0, 1, 0)]
          rescue Parser::SyntaxError
            start_offset -= 1
            retry
          ensure
            $stderr = old_stderr
          end
        else
          ast = @asts_by_file.fetch(region.path) do
            path = region.path
            code =
            if path.is_a?(Array) && File.basename(path.first, ".rb") =~ /boot(\d+)?/
              $boot_code.fetch(File.basename(path.first, ".rb"))
            else
              File.read(path)
            end
            @asts_by_file[path] = Parser::CurrentRuby.parse(code)
          end
          [ast, region]
        end
      end

      def in_repl(file_path)
        file_path == "(irb)" || file_path == "(pry)"
      end

      def find_proc(node, region)
        return [] unless node.is_a?(Parser::AST::Node)
        result = []
        is_match = node.type == :block && node.location.begin.line == region.begin_line
        result << node if is_match
        result += node.children.flat_map { |c| find_proc(c, region) }.reject(&:nil?)
        result
      end
    end
  end
  # require_glob 'destruct/**/*.rb'
  # frozen_string_literal: true

  require 'active_support/core_ext/object/deep_dup'
  # require_relative 'types'
  # frozen_string_literal: true

  # require_relative './monkeypatch'

  class Destruct
    # Accept any value
    Any = make_singleton("#<Any>")

    module Binder
    end

    # Bind a single value
    Var = Struct.new(:name)
    class Var
      include Binder

      def initialize(name)
        self.name = name
      end

      def inspect
        "#<Var: #{name}>"
      end
      alias_method :to_s, :inspect
    end

    # Bind zero or more values
    Splat = Struct.new(:name)
    class Splat
      include Binder

      def initialize(name)
        self.name = name
      end

      def inspect
        "#<Splat: #{name}>"
      end
      alias_method :to_s, :inspect
    end

    # hash patterns matched within the given pattern will be matched strictly,
    # i.e., the hash being matched must have the exact same key set (no extras allowed).
    Strict = Struct.new(:pat)
    class Strict
      def inspect
        "#<Strict: #{pat}>"
      end
      alias_method :to_s, :inspect
    end

    # Bind a value but continue to match a subpattern
    Let = Struct.new(:name, :pattern)
    class Let
      include Binder

      def initialize(name, pattern)
        self.name = name
        self.pattern = pattern
      end

      def inspect
        "#<Let: #{name} = #{pattern}>"
      end
      alias_method :to_s, :inspect
    end

    # A subpattern supplied by a match-time expression
    Unquote = Struct.new(:code_expr)
    class Unquote
      def inspect
        "#<Unquote: #{code_expr}>"
      end
      alias_method :to_s, :inspect
    end

    # Match an object of a particular type with particular fields
    Obj = Struct.new(:type, :fields)
    class Obj
      def initialize(type, fields={})
        unless type.is_a?(Class) || type.is_a?(Module)
          raise "Obj type must be a Class or a Module, was: #{type}"
        end
        self.type = type
        self.fields = fields
      end

      def inspect
        "#<Obj: #{type}[#{fields.map { |(k, v)| "#{k}: #{v.inspect}"}.join(", ")}]>"
      end
      alias_method :to_s, :inspect
    end

    # Bind based on the first pattern that matches
    Or = Struct.new(:patterns)
    class Or
      def initialize(*patterns)
        self.patterns = flatten(patterns)
      end

      def inspect
        "#<Or: #{patterns.map(&:inspect).join(", ")}>"
      end
      alias_method :to_s, :inspect

      private

      def flatten(ps)
        ps.inject([]) {|acc, p| p.is_a?(Or) ? acc + p.patterns : acc << p}
      end
    end
  end
  require 'stringio'
  # require_relative './compiler'
  # frozen_string_literal: true

  require "pp"
  # require_relative './rbeautify'
  # frozen_string_literal: true

  # rubocop:disable all

=begin
/***************************************************************************
 *   Copyright (C) 2008, Paul Lutus                                        *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
 ***************************************************************************/
=end

  class Destruct
    module RBeautify

      # user-customizable values

      RBeautify::TabStr = " "
      RBeautify::TabSize = 2

      # indent regexp tests

      IndentExp = [
        /^module\b/,
        /^class\b/,
        /^if\b/,
        /(=\s*|^)until\b/,
        /(=\s*|^)for\b/,
        /^unless\b/,
        /(=\s*|^)while\b/,
        /(=\s*|^)begin\b/,
        /(^| )case\b/,
        /\bthen\b/,
        /^rescue\b/,
        /^def\b/,
        /\bdo\b/,
        /^else\b/,
        /^elsif\b/,
        /^ensure\b/,
        /\bwhen\b/,
        /\{[^\}]*$/,
        /\[[^\]]*$/
      ]

      # outdent regexp tests

      OutdentExp = [
        /^rescue\b/,
        /^ensure\b/,
        /^elsif\b/,
        /^end\b/,
        /^else\b/,
        /\bwhen\b/,
        /^[^\{]*\}/,
        /^[^\[]*\]/
      ]

      def RBeautify.rb_make_tab(tab)
        return (tab < 0)?"":TabStr * TabSize * tab
      end

      def RBeautify.rb_add_line(line,tab)
        line.strip!
        line = rb_make_tab(tab) + line if line.length > 0
        return line
      end

      def RBeautify.beautify_string(source, path = "")
        comment_block = false
        in_here_doc = false
        here_doc_term = ""
        program_end = false
        multiLine_array = []
        multiLine_str = ""
        tab = 0
        output = []
        source.each do |line|
          line.chomp!
          if(!program_end)
            # detect program end mark
            if(line =~ /^__END__$/)
              program_end = true
            else
              # combine continuing lines
              if(!(line =~ /^\s*#/) && line =~ /[^\\]\\\s*$/)
                multiLine_array.push line
                multiLine_str += line.sub(/^(.*)\\\s*$/,"\\1")
                next
              end

              # add final line
              if(multiLine_str.length > 0)
                multiLine_array.push line
                multiLine_str += line.sub(/^(.*)\\\s*$/,"\\1")
              end

              tline = ((multiLine_str.length > 0)?multiLine_str:line).strip
              if(tline =~ /^=begin/)
                comment_block = true
              end
              if(in_here_doc)
                in_here_doc = false if tline =~ %r{\s*#{here_doc_term}\s*}
              else # not in here_doc
                if tline =~ %r{=\s*<<}
                  here_doc_term = tline.sub(%r{.*=\s*<<-?\s*([_|\w]+).*},"\\1")
                  in_here_doc = here_doc_term.size > 0
                end
              end
            end
          end
          if(comment_block || program_end || in_here_doc)
            # add the line unchanged
            output << line
          else
            comment_line = (tline =~ /^#/)
            if(!comment_line)
              # throw out sequences that will
              # only sow confusion
              while tline.gsub!(/\{[^\{]*?\}/,"")
              end
              while tline.gsub!(/\[[^\[]*?\]/,"")
              end
              while tline.gsub!(/'.*?'/,"")
              end
              while tline.gsub!(/".*?"/,"")
              end
              while tline.gsub!(/\`.*?\`/,"")
              end
              while tline.gsub!(/\([^\(]*?\)/,"")
              end
              while tline.gsub!(/\/.*?\//,"")
              end
              while tline.gsub!(/%r(.).*?\1/,"")
              end
              # delete end-of-line comments
              tline.sub!(/#[^\"]+$/,"")
              # convert quotes
              tline.gsub!(/\\\"/,"'")
              OutdentExp.each do |re|
                if(tline =~ re)
                  tab -= 1
                  break
                end
              end
            end
            if (multiLine_array.length > 0)
              multiLine_array.each do |ml|
                output << rb_add_line(ml,tab)
              end
              multiLine_array.clear
              multiLine_str = ""
            else
              output << rb_add_line(line,tab)
            end
            if(!comment_line)
              IndentExp.each do |re|
                if(tline =~ re && !(tline =~ /\s+end\s*$/))
                  tab += 1
                  break
                end
              end
            end
          end
          if(tline =~ /^=end/)
            comment_block = false
          end
        end
        error = (tab != 0)
        STDERR.puts "Error: indent/outdent mismatch: #{tab}." if error
        return output.join("\n") + "\n",error
      end # beautify_string

      def RBeautify.beautify_file(path)
        error = false
        if(path == '-') # stdin source
          source = STDIN.read
          dest,error = beautify_string(source,"stdin")
          print dest
        else # named file source
          source = File.read(path)
          dest,error = beautify_string(source,path)
          if(source != dest)
            # make a backup copy
            File.open(path + "~","w") { |f| f.write(source) }
            # overwrite the original
            File.open(path,"w") { |f| f.write(dest) }
          end
        end
        return error
      end # beautify_file

      def RBeautify.main
        error = false
        if(!ARGV[0])
          STDERR.puts "usage: Ruby filenames or \"-\" for stdin."
          exit 0
        end
        ARGV.each do |path|
          error = (beautify_file(path))?true:error
        end
        error = (error)?1:0
        exit error
      end # main
    end # module RBeautify
  end

  # if launched as a standalone program, not loaded as a module
  if __FILE__ == $0
    RBeautify.main
  end
  # rubocop:enable all
  # require_relative './code_gen'
  # frozen_string_literal: true

  require 'stringio'

  class Destruct
    # Helper methods for generating code
    module CodeGen
      GeneratedCode = Struct.new(:proc, :code, :filename)
      class GeneratedCode
        def inspect
          "#<GeneratedCode: #{filename}>"
        end

        def show
          CodeGen.show_code(self)
        end
      end

      def emitted
        @emitted ||= StringIO.new
      end

      def emit(str)
        emitted << str
        emitted << "\n"
      end

      def generate(filename='', line=1)
      code = <<~CODE
        # frozen_string_literal: true
        lambda do |_code, _filename, _refs#{ref_args}|
          #{emitted.string}
        end
      CODE
      code = beautify_ruby(code)
      begin
        result = eval(code, nil, filename, line - 2).call(code, filename, refs, *refs.values)
        gc = GeneratedCode.new(result, code, filename)
        show_code(gc) if Destruct.show_code
        gc
      rescue SyntaxError
        show_code(code, filename, refs, fancy: false, include_vm: false)
        raise
      end
    end

    def self.quick_gen(filename='', line=1, &block)
      Class.new do
        include CodeGen
        define_method(:initialize) do
          instance_exec(&block)
        end
      end.new.generate(filename, line)
    end

    def show_code_on_error
      emit_begin do
        yield
      end.rescue do
        emit "Destruct::CodeGen.show_code(_code, _filename, _refs, fancy: false)"
        emit "raise"
      end.end
    end

    def emit_begin
      emit "begin"
      yield
      Begin.new(self)
    end

    def emit_lambda(*args, &emit_body)
      emit "lambda do |#{args.join(", ")}|"
      emit_body.call
      emit "end"
    end

    def emit_if(cond)
      emit "if #{cond}"
      yield
      If.new(self)
    end

    class If
      def initialize(parent)
        @parent = parent
      end

      def elsif(cond)
        @parent.instance_exec do
          emit "elsif #{cond}"
          yield
        end
        self
      end

      def else
        @parent.instance_exec do
          emit "else"
          yield
          emit "end"
        end
        self
      end

      def end
        @parent.instance_exec do
          emit "end"
        end
      end
    end

    class Begin
      def initialize(parent)
        @parent = parent
      end

      def rescue(type_clause="")
        @parent.instance_exec do
          emit "rescue #{type_clause}"
          yield
        end
        self
      end

      def end
        @parent.instance_exec do
          emit "end"
        end
      end
    end

    private def ref_args
      return "" if refs.none?
      width = refs.keys.map(&:to_s).map(&:size).max
      ", \n#{refs.map { |k, v| "#{k.to_s.ljust(width)}, # #{v.inspect}" }.join("\n")}\n"
    end

    def beautify_ruby(code)
      Destruct::RBeautify.beautify_string(code.split("\n").reject { |line| line.strip == '' }).first
    end

    def refs
      @refs ||= {}
    end

    def reverse_refs
      @reverse_refs ||= {}
    end

    # obtain a runtime reference to a compile-time value
    def get_ref(value, id=nil)
      reverse_refs.fetch(value) do
        if id
          raise "ref #{id} is already bound" if refs.keys.include?(id)
        else
          id = get_temp
        end
        refs[id] = value
        reverse_refs[value] = id
        id
      end
    end

    # obtain a unique temporary identifier
    def get_temp(prefix="t")
      @temp_num ||= 0
      "_#{prefix}#{@temp_num += 1}"
    end

    module_function

    def show_code(code, filename="", refs=(self.respond_to?(:refs) ? self.refs : {}),
                  fancy: false, include_vm: false, seen: [])
      if code.is_a?(GeneratedCode)
        gc = code
        code = gc.code
        filename = gc.filename
      end
      return if seen.include?(code)
      seen << code
      refs.values.each do |v|
        if v.is_a?(CompiledPattern)
          show_code(v.generated_code, seen: seen)
        elsif v.is_a?(GeneratedCode)
          show_code(v, seen: seen)
        end
      end
      lines = number_lines(code, -2) # -2 to line up with stack traces
      if fancy
        lines = lines
                    .reject { |line| line =~ /^\s*\d+\s*puts/ }
                    .map do |line|
          if line !~ /, #|_code|_refs/
            refs.each do |k, v|
              line = line.gsub(/#{k}(?!\d+)/, v.inspect)
            end
          end
          line
        end
      end
      puts
      puts filename
      puts lines
      if include_vm
        pp RubyVM::InstructionSequence.compile(code).to_a
      end
    end

    def number_lines(code, offset=0)
      code.split("\n").each_with_index.map do |line, n|
        "#{(n + 1 + offset).to_s.rjust(3)} #{line}"
      end
    end
  end
end
require "set"

class Destruct
  class Compiler
    include CodeGen

    class << self
      def compile(pat)
        if pat.is_a?(CompiledPattern)
          pat
        else
          compiled_patterns.fetch(pat) do # TODO: consider caching by object_id
            compiled_patterns[pat] = begin
              cp = Compiler.new.compile(pat)
              on_compile_handlers.each { |h| h.(pat) }
              cp
            end
          end
        end
      end

      def compiled_patterns
        Thread.current[:__boot1_destruct_compiled_patterns__] ||= {}
      end

      def match(pat, x)
        compile(pat).match(x)
      end

      def on_compile(&block)
        on_compile_handlers << block
      end

      private def on_compile_handlers
        @on_compile_handlers ||= []
      end
    end

    Frame = Struct.new(:pat, :x, :env, :parent, :type)

    def initialize
      @known_real_envs ||= Set.new
    end

    def compile(pat)
      @var_counts = var_counts(pat)
      @var_names = @var_counts.keys
      if @var_names.any?
        get_ref(Destruct::Env.new_class(*@var_names).method(:new), "_make_env")
      end

      x = get_temp("x")
      env = get_temp("env")
      emit_lambda(x, "_binding") do
        show_code_on_error do
          emit "#{env} = true"
          match(Frame.new(pat, x, env))
          emit env
        end
      end
      g = generate("Matcher for: #{pat.inspect.gsub(/\s+/, " ")}")
      CompiledPattern.new(pat, g, @var_names)
    end

    def var_counts(pat)
      find_var_names_non_uniq(pat).group_by(&:itself).map { |k, vs| [k, vs.size] }.to_h
    end

    def find_var_names_non_uniq(pat)
      if pat.is_a?(Obj)
        pat.fields.values.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Or)
        @has_or = true
        pat.patterns.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Let)
        [pat.name, *find_var_names_non_uniq(pat.pattern)]
      elsif pat.is_a?(Binder)
        [pat.name]
      elsif pat.is_a?(Hash)
        pat.values.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Array)
        pat.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Regexp)
        pat.named_captures.keys.map(&:to_sym)
      elsif pat.is_a?(Strict)
        find_var_names_non_uniq(pat.pat)
      else
        []
      end
    end

    def match(s)
      if s.pat == Any
        # do nothing
      elsif s.pat.is_a?(Obj)
        match_obj(s)
      elsif s.pat.is_a?(Or)
        match_or(s)
      elsif s.pat.is_a?(Let)
        match_let(s)
      elsif s.pat.is_a?(Var)
        match_var(s)
      elsif s.pat.is_a?(Unquote)
        match_unquote(s)
      elsif s.pat.is_a?(Hash)
        match_hash(s)
      elsif s.pat.is_a?(Array)
        match_array(s)
      elsif s.pat.is_a?(Regexp)
        match_regexp(s)
      elsif s.pat.is_a?(Strict)
        match_strict(s)
      elsif is_literal_val?(s.pat)
        match_literal(s)
      elsif
      match_other(s)
      end
    end

    def is_literal_val?(x)
      x.is_a?(Numeric) || x.is_a?(String) || x.is_a?(Symbol)
    end

    def is_literal_pat?(p)
      !(p.is_a?(Obj) ||
          p.is_a?(Or) ||
          p.is_a?(Binder) ||
          p.is_a?(Unquote) ||
          p.is_a?(Hash) ||
          p.is_a?(Array))
    end

    def pattern_order(p)
      # check the cheapest or most likely to fail first
      if is_literal_pat?(p)
        0
      elsif p.is_a?(Or) || p.is_a?(Regexp)
        2
      elsif p.is_a?(Binder)
        3
      elsif p.is_a?(Unquote)
        4
      else
        1
      end
    end

    def match_array(s)
      s.type = :array
      splat_count = s.pat.count { |p| p.is_a?(Splat) }
      if splat_count > 1
        raise "An array pattern cannot have more than one splat: #{s.pat}"
      end
      splat_index = s.pat.find_index { |p| p.is_a?(Splat) }
      is_closed = !splat_index || splat_index != s.pat.size - 1
      pre_splat_range = 0...(splat_index || s.pat.size)

      s.x = localize(nil, s.x)
      known_real_envs_before = @known_real_envs.dup
      emit_if "#{s.x}.is_a?(Array)" do
        cond = splat_index ? "#{s.x}.size >= #{s.pat.size - 1}" : "#{s.x}.size == #{s.pat.size}"
        test(s, cond) do

          pre_splat_range
              .map { |i| [s.pat[i], i] }
              .sort_by { |(item_pat, i)| [pattern_order(item_pat), i] }
              .each do |item_pat, i|
            x = localize(item_pat, "#{s.x}[#{i}]")
            match(Frame.new(item_pat, x, s.env, s))
          end

          if splat_index
            splat_range = get_temp("splat_range")
            post_splat_width = s.pat.size - splat_index - 1
            emit "#{splat_range} = #{splat_index}...(#{s.x}.size#{post_splat_width > 0 ? "- #{post_splat_width}" : ""})"
            bind(s, s.pat[splat_index], "#{s.x}[#{splat_range}]")

            post_splat_pat_range = ((splat_index + 1)...s.pat.size)
            post_splat_pat_range.each do |i|
              item_pat = s.pat[i]
              x = localize(item_pat, "#{s.x}[-#{s.pat.size - i}]")
              match(Frame.new(item_pat, x, s.env, s))
            end
          end
        end
      end.elsif "#{s.x}.is_a?(Enumerable)" do
        @known_real_envs = known_real_envs_before
        en = get_temp("en")
        done = get_temp("done")
        stopped = get_temp("stopped")
        emit "#{en} = #{s.x}.each"
        emit "#{done} = false"
        emit_begin do
          s.pat[0...(splat_index || s.pat.size)].each do |item_pat|
            x = localize(item_pat, "#{en}.next")
            match(Frame.new(item_pat, x, s.env, s))
          end

          if splat_index
            if is_closed
              splat = get_temp("splat")
              emit "#{splat} = []"
              splat_len = get_temp("splat_len")
              emit "#{splat_len} = #{s.x}.size - #{s.pat.size - 1}"
              emit "#{splat_len}.times do"
              emit "#{splat} << #{en}.next"
              emit "end"
              bind(s, s.pat[splat_index], splat)

              s.pat[(splat_index+1)...(s.pat.size)].each do |item_pat|
                x = localize(item_pat, "#{en}.next")
                match(Frame.new(item_pat, x, s.env, s))
              end
            else
              bind(s, s.pat[splat_index], "#{en}.new_from_here")
            end
          end

          emit "#{done} = true"
          emit "#{en}.next" if is_closed
        end.rescue "StopIteration" do
          emit "#{stopped} = true"
          test(s, done)
        end.end
        test(s, stopped) if is_closed
      end.else do
        test(s, "nil")
      end
    end

    def in_or(s)
      !s.nil? && (s.type == :or || in_or(s.parent))
    end

    def in_strict(s)
      !s.nil? && (s.pat.is_a?(Strict) || in_strict(s.parent))
    end

    def match_regexp(s)
      s.type = :regexp
      m = get_temp("m")
      match_env = get_temp("env")
      test(s, "#{s.x}.is_a?(String) || #{s.x}.is_a?(Symbol)") do
        emit "#{m} = #{get_ref(s.pat)}.match(#{s.x})"
        emit "#{match_env} = Destruct::Env.new(#{m}) if #{m}"
        test(s, match_env)
        merge(s, match_env, dynamic: true)
      end
    end

    def match_strict(s)
      match(Frame.new(s.pat.pat, s.x, s.env, s))
    end

    def match_literal(s)
      s.type = :literal
      test(s, "#{s.x} == #{s.pat.inspect}")
    end

    def match_other(s)
      s.type = :other
      test(s, "#{s.x} == #{get_ref(s.pat)}")
    end

    def test(s, cond)
      # emit "puts \"line #{emitted_line_count + 8}: \#{#{cond.inspect}}\""
      emit "puts \"test: \#{#{cond.inspect}}\"" if $show_tests
      if in_or(s)
        emit "#{s.env} = (#{cond}) ? #{s.env} : nil if #{s.env}"
        if block_given?
          emit_if s.env do
            yield
          end.end
        end
      elsif cond == "nil" || cond == "false"
        emit "return nil"
      else
        emit "#{cond} or return nil"
        yield if block_given?
      end
    end

    def match_var(s)
      s.type = :var
      test(s, "#{s.x} != #{nothing_ref}")
      bind(s, s.pat, s.x)
    end

    def match_unquote(s)
      temp_env = get_temp("env")
      emit "raise 'binding must be provided' if _binding.nil?"
      emit "#{temp_env} = Destruct.match((_binding.respond_to?(:call) ? _binding.call : _binding).eval('#{s.pat.code_expr}'), #{s.x}, _binding)"
      test(s, temp_env)
      merge(s, temp_env, dynamic: true)
    end

    def match_let(s)
      s.type = :let
      match(Frame.new(s.pat.pattern, s.x, s.env, s))
      bind(s, s.pat, s.x)
    end

    def bind(s, var, val, val_could_be_unbound_sentinel=false)
      var_name = var.is_a?(Binder) ? var.name : var

      # emit "# bind #{var_name}"
      proposed_val =
          if val_could_be_unbound_sentinel
            # we'll want this in a local because the additional `if` clause below will need the value a second time.
            pv = get_temp("proposed_val")
            emit "#{pv} = #{val}"
            pv
          else
            val
          end

      do_it = proc do
        unless @known_real_envs.include?(s.env)
          # no need to ensure the env is real (i.e., an Env, not `true`) if it's already been ensured
          emit "#{s.env} = _make_env.() if #{s.env} == true"
          @known_real_envs.add(s.env) unless in_or(s)
        end
        current_val = "#{s.env}.#{var_name}"
        if @var_counts[var_name] > 1
          # if the pattern binds the var in two places, we'll have to check if it's already bound
          emit_if "#{current_val} == :__boot1_unbound__" do
            emit "#{s.env}.#{var_name} = #{proposed_val}"
          end.elsif "#{current_val} != #{proposed_val}" do
            if in_or(s)
              emit "#{s.env} = nil"
            else
              test(s, "nil")
            end
          end.end
        else
          # otherwise, this is the only place we'll attempt to bind this var, so just do it
          emit "#{current_val} = #{proposed_val}"
        end
      end

      if in_or(s)
        emit_if("#{s.env}", &do_it).end
      elsif val_could_be_unbound_sentinel
        emit_if("#{s.env} && #{proposed_val} != :__boot1_unbound__", &do_it).end
      else
        do_it.()
      end

      test(s, "#{s.env}") if in_or(s)
    end

    def match_obj(s)
      s.type = :obj
      match_hash_or_obj(s, get_ref(s.pat.type), s.pat.fields, proc { |field_name| "#{s.x}.#{field_name}" })
    end

    def match_hash(s)
      s.type = :hash
      match_hash_or_obj(s, "Hash", s.pat, proc { |field_name| "#{s.x}.fetch(#{field_name.inspect}, #{nothing_ref})" },
                        "#{s.x}.keys.sort == #{get_ref(s.pat.keys.sort)}")
    end

    def nothing_ref
      get_ref(Destruct::NOTHING)
    end

    def match_hash_or_obj(s, type_str, pairs, make_x_sub, strict_test=nil)
      test(s, "#{s.x}.is_a?(#{type_str})") do
        keep_matching = proc do
          pairs
              .sort_by { |(_, field_pat)| pattern_order(field_pat) }
              .each do |field_name, field_pat|
            x = localize(field_pat, make_x_sub.(field_name), field_name)
            match(Frame.new(field_pat, x, s.env, s))
          end
        end

        if in_strict(s) && strict_test
          test(s, strict_test) { keep_matching.call }
        else
          keep_matching.call
        end
      end
    end

    def multi?(pat)
      pat.is_a?(Or) ||
          (pat.is_a?(Array) && pat.size > 1) ||
          pat.is_a?(Obj) && pat.fields.any?
    end

    def match_or(s)
      s.type = :or
      closers = []
      or_env = get_temp("env")
      emit "#{or_env} = true"
      s.pat.patterns.each_with_index do |alt, i|
        match(Frame.new(alt, s.x, or_env, s))
        if i < s.pat.patterns.size - 1
          emit "unless #{or_env}"
          closers << proc { emit "end" }
          emit "#{or_env} = true"
        end
      end
      closers.each(&:call)
      merge(s, or_env)
      emit "#{s.env} or return nil" if !in_or(s.parent)
    end

    def merge(s, other_env, dynamic: false)
      @known_real_envs.include?(s.env)

      emit_if("#{s.env}.nil? || #{other_env}.nil?") do
        emit "#{s.env} = nil"
      end.elsif("#{s.env} == true") do
        emit "#{s.env} = #{other_env}"
      end.elsif("#{other_env} != true") do
        if dynamic
          emit "#{other_env}.env_each do |k, v|"
          emit_if("#{s.env}[k] == :__boot1_unbound__") do
            emit "#{s.env}[k] = v"
          end.elsif("#{s.env}[k] != v") do
            if in_or(s)
              emit "#{s.env} = nil"
            else
              test(s, "nil")
            end
          end.end
          emit "end"
        else
          @var_names.each do |var_name|
            bind(s, var_name, "#{other_env}.#{var_name}", true)
          end
        end
      end.end
    end

    private

    def localize(pat, x, prefix="t")
      prefix = prefix.to_s.gsub(/[^\w\d_]/, '')
      if (pat.nil? && x =~ /\.\[\]/) || multi?(pat) || (pat.is_a?(Binder) && x =~ /\.fetch|\.next/)
        t = get_temp(prefix)
        emit "#{t} = #{x}"
        x = t
      end
      x
    end
  end

  class Pattern
    attr_reader :pat

    def initialize(pat)
      @pat = pat
    end

    def to_s
      "#<Pattern #{pat}>"
    end

    alias_method :inspect, :to_s

    def match(x, binding=nil)
      Compiler.compile(pat).match(x, binding)
    end
  end

  class CompiledPattern
    attr_reader :pat, :generated_code, :var_names

    def initialize(pat, generated_code, var_names)
      @pat = pat
      @generated_code = generated_code
      @var_names = var_names
    end

    def match(x, binding=nil)
      @generated_code.proc.(x, binding)
    end

    def show_code
      generated_code.show
    end
  end
end

module Enumerable
  def rest
    result = []
    while true
      result << self.next
    end
  rescue StopIteration
    result
  end

  def new_from_here
    orig = self
    WrappedEnumerator.new(orig) do |y|
      while true
        y << orig.next
      end
    end
  end
end

class WrappedEnumerator < Enumerator
  def initialize(inner, &block)
    super(&block)
    @inner = inner
  end

  def new_from_here
    orig = @inner
    WrappedEnumerator.new(orig) do |y|
      while true
        y << orig.next
      end
    end
  end
end

class Destruct
  class Transformer
    DEBUG = false
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
        if DEBUG || Destruct.show_transformations
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
            next unless validate_constraints(args, rule.constraints)
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

    def validate_constraints(args, constraints)
      constraints.each_pair do |var, const|
        return false unless validate_constraint(args[var], const)
      end
    end

    def validate_constraint(x, c)
      if c.is_a?(Module)
        x.is_a?(c)
      elsif c.is_a?(Array) && c.size == 1
        return false unless x.is_a?(Array) || x.is_a?(Hash)
        vs = x.is_a?(Array) ? x : x.values
        vs.all? { |v| validate_constraint(v, c[0]) }
      elsif c.is_a?(Array)
        c.any? { |c| validate_constraint(x, c) }
      elsif c.respond_to?(:call)
        c.(x)
      end
    end

    def apply_template(x, rule, args=[], kws={})
      if proc_has_kw(rule.template, :binding)
        if @binding.nil?
          raise 'binding must be provided'
        end
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
# require_glob 'destruct/**/*.rb'
# require_relative './rule_sets/helpers'
class Destruct
  module RuleSets
    module Helpers
      def n(type, children=[])
        Obj.new(Parser::AST::Node, type: type, children: children)
      end

      def v(name)
        Var.new(name)
      end

      def s(name)
        Splat.new(name)
      end

      def any(*alt_patterns)
        if alt_patterns.none?
          Any
        else
          Or.new(*alt_patterns)
        end
      end

      def let(name, pat)
        Let.new(name, pat)
      end
    end
  end
end

class Destruct
  module RuleSet
    DEBUG = false

    def rules
      @rules ||= []
    end

    def self.included(base)
      base.extend(ClassMethods)
      base.include(RuleSets::Helpers)
    end

    module ClassMethods
      def transform(x=NOTHING, binding: nil, **hash_arg, &x_proc)
        instance.transform(x, binding: binding, **hash_arg, &x_proc)
      end

      def instance
        @instance ||= new
      end
    end

    def transform(x=NOTHING, binding: nil, **hash_arg, &x_proc)
      if x != NOTHING && x_proc
        raise "Pass either x or a block but not both"
      end
      x = x == NOTHING && x_proc.nil? ? hash_arg : x # ruby interprets a hash arg as keywords rather than a value for x
      x = x != NOTHING ? x : x_proc
      x = x.is_a?(Proc) ? ExprCache.get(x) : x
      binding ||= x_proc&.binding
      result = Transformer.transform(x == NOTHING ? x_proc : x, self, binding)
      self.validate(result) if self.respond_to?(:validate)
      result
    end

    # @param pat_or_proc [Object] One of:
    #   an AST-matching destruct pattern,
    #   a proc containing syntax for a meta rule set to convert into an AST-matching destruct pattern, or
    #   a class.
    # The block should take keyword parameters that match the names of variables bound by the pattern.
    # These values are fully transformed before being passed to the block. To obtain the untransformed
    # syntax of variable "x", the block may request parameter "raw_x" instead. The block may also request
    # the special parameters "binding" and/or "transform". "binding" is the Binding within which the pattern
    # is being evaluated. "transform" is the transformation method, which allows the block to insert itself
    # into the recursive transformation process.
    def add_rule(pat_or_proc, constraints={}, &translate_block)
      if pat_or_proc.is_a?(Proc)
        node = ExprCache.get(pat_or_proc)
        pat = (@meta_rule_set || RuleSets::AstToPattern).transform(node)
        rules << Transformer::Rule.new(pat, translate_block, constraints)
      else
        rules << Transformer::Rule.new(pat_or_proc, translate_block, constraints)
      end
    end

    private

    def meta_rule_set(rule_set)
      @meta_rule_set = rule_set
    end

    def add_rule_set(rule_set)
      if rule_set.is_a?(Class)
        rule_set = rule_set.instance
      end
      rule_set.rules.each { |r| rules << r }
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'stringio'

class Destruct
  # Holds the variables bound during pattern matching. For many patterns, the variable
  # names are known at compilation time, so Env.new_class is used to create a derived
  # Env that can hold exactly those variables. If a pattern contains a Regex, Or, or
  # Unquote, then the variables bound are generally not known until the pattern is matched
  # against a particular object at run time. The @extras hash is used to bind these variables.
  class Env
    NIL = Object.new
    UNBOUND = :__boot1_unbound__

    def method_missing(name, *args, &block)
      name_str = name.to_s
      if name_str.end_with?('=')
        @extras ||= {}
        @extras[name_str[0..-2].to_sym] = args[0]
      else
        if @extras.nil?
          Destruct::Env::UNBOUND
        else
          @extras.fetch(name) { Destruct::Env::UNBOUND }
        end
      end
    end

    def initialize(regexp_match_data=nil)
      if regexp_match_data
        @extras = regexp_match_data.names.map { |n| [n.to_sym, regexp_match_data[n]] }.to_h
      end
    end

    def env_each
      if @extras
        @extras.each_pair { |k, v| yield(k, v) }
      end
    end

    def env_keys
      result = []
      env_each { |k, _| result.push(k) }
      result
    end

    # deprecated
    def [](var_name)
      self.send(var_name)
    end

    # only for dynamic binding
    def []=(var_name, value)
      self.send(:"#{var_name}=", value)
    end

    def to_s
      kv_strs = []
      env_each do |k, v|
        kv_strs << "#{k}=#{v.inspect}"
      end
      "#<Env: #{kv_strs.join(", ")}>"
    end
    alias_method :inspect, :to_s

    def self.new_class(*var_names)
      Class.new(Env) do
        attr_accessor(*var_names)
        eval <<~CODE
          def initialize
            #{var_names.map { |v| "@#{v} = :__boot1_unbound__" }.join("\n")}
          end

          def env_each
            #{var_names.map { |v| "yield(#{v.inspect}, @#{v})" }.join("\n")}
            if @extras
              @extras.each_pair { |k, v| yield(k, v) }
            end
          end

          def self.name; "Destruct::Env"; end
        CODE
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'unparser'

class Destruct
  include CodeGen

  NOTHING = make_singleton("#<NOTHING>")

  class << self
    attr_accessor :show_code, :show_transformations

    def instance
      Thread.current[:__boot1_destruct_cache_instance__] ||= Destruct.new
    end

    def get_compiled(p, get_binding=nil)
      instance.get_compiled(p, get_binding)
    end

    def destruct(value, &block)
      instance.destruct(value, &block)
    end
  end

  def self.match(pat, x, binding=nil)
    if pat.is_a?(Proc)
      pat = RuleSets::StandardPattern.transform(binding: binding, &pat)
    end
    Compiler.compile(pat).match(x, binding)
  end

  def initialize(rule_set=RuleSets::StandardPattern)
    @rule_set = rule_set
  end

  def get_compiled(p, get_binding)
    @cpats_by_proc_id ||= {}
    key = p.source_location_id
    @cpats_by_proc_id.fetch(key) do
      binding = get_binding.call # obtaining the proc binding allocates heap, so only do so when necessary
      @cpats_by_proc_id[key] = Compiler.compile(@rule_set.transform(binding: binding, &p))
    end
  end

  def destruct(value, &block)
    context = contexts.pop || Context.new
    begin
      cached_binding = nil
      context.init(self, value) { cached_binding ||= block.binding }
      context.instance_exec(&block)
    ensure
      contexts.push(context)
    end
  end

  def contexts
    # Avoid allocations by keeping a stack for each thread. Maximum stack depth of 100 should be plenty.
    Thread.current[:__boot1_destruct_contexts__] ||= [] # Array.new(100) { Context.new }
  end

  class Context
    # BE CAREFUL TO MAKE SURE THAT init() clears all instance vars

    def init(parent, value, &get_outer_binding)
      @parent = parent
      @value = value
      @get_outer_binding = get_outer_binding
      @env = nil
      @outer_binding = nil
      @outer_self = nil
    end

    def match(pat=nil, &pat_proc)
      cpat = pat ? Compiler.compile(pat) : @parent.get_compiled(pat_proc, @get_outer_binding)
      @env = cpat.match(@value, @get_outer_binding)
    end

    def outer_binding
      @outer_binding ||= @get_outer_binding.call
    end

    def outer_self
      @outer_self ||= outer_binding.eval("self")
    end

    def method_missing(method, *args, &block)
      bound_value = @env.is_a?(Env) ? @env[method] : Env::UNBOUND
      if bound_value != Env::UNBOUND
        bound_value
      elsif outer_self
        outer_self.send method, *args, &block
      else
        super
      end
    end
  end
end

def destruct(value, &block)
  Destruct.destruct(value, &block)
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

# require_relative './ruby'
# frozen_string_literal: true

# require_relative './unpack_enumerables'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class UnpackEnumerables
      include RuleSet
      include Helpers

      def initialize
        add_rule(Array) { |a, transform:| a.map { |v| transform.(v) } }
        add_rule(Hash) { |h, transform:| h.map { |k, v| [transform.(k), transform.(v)] }.to_h }
      end

      class VarRef
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_s
          "#<VarRef: #{name}>"
        end
        alias_method :inspect, :to_s
      end

      class ConstRef
        attr_reader :fqn

        def initialize(fqn)
          @fqn = fqn
        end

        def to_s
          "#<ConstRef: #{fqn}>"
        end
        alias_method :inspect, :to_s
      end
    end
  end
end

class Object
  def transformer_eql?(other)
    self == other
  end
end

class Destruct
  module RuleSets
    class Ruby
      include RuleSet
      include Helpers

      def initialize
        add_rule(n(any(:int, :sym, :float, :str), [v(:value)])) { |value:| value }
        add_rule(n(:nil, [])) { nil }
        add_rule(n(:true, [])) { true }
        add_rule(n(:false, [])) { false }
        add_rule(n(:array, v(:items))) { |items:| items }
        add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
        add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
        add_rule(n(:lvar, [v(:name)])) { |name:| VarRef.new(name) }
        add_rule(n(:send, [nil, v(:name)])) { |name:| VarRef.new(name) }
        add_rule(n(:const, [v(:parent), v(:name)]), parent: [ConstRef, NilClass]) do |parent:, name:|
          ConstRef.new([parent&.fqn, name].compact.join("::"))
        end
        add_rule(n(:cbase)) { ConstRef.new("") }
        add_rule(let(:matched, n(:regexp, any))) { |matched:| eval(unparse(matched)) }
        add_rule_set(UnpackEnumerables)
      end

      class VarRef
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_s
          "#<VarRef: #{name}>"
        end
        alias_method :inspect, :to_s
      end

      class ConstRef
        attr_reader :fqn

        def initialize(fqn)
          @fqn = fqn
        end

        def to_s
          "#<ConstRef: #{fqn}>"
        end
        alias_method :inspect, :to_s
      end

      def m(type, *children)
        Parser::AST::Node.new(type, children)
      end
    end
  end
end
# require_relative './pattern_validator'
class Destruct
  module RuleSets
    # Used to verify a transformer hasn't left any untransformed syntax around
    class PatternValidator
      class << self
        def validate(x)
          if x.is_a?(Or)
            x.patterns.each { |v| validate(v) }
          elsif x.is_a?(Obj)
            x.fields.values.each { |v| validate(v) }
          elsif x.is_a?(Let)
            validate(x.pattern)
          elsif x.is_a?(Array)
            x.each { |v| validate(v) }
          elsif x.is_a?(Strict)
            validate(x.pat)
          elsif x.is_a?(Hash)
            unless x.keys.all? { |k| k.is_a?(Symbol) }
              raise "Invalid pattern: #{x}"
            end
            x.values.each { |v| validate(v) }
          elsif !(x.is_a?(Binder) || x.is_a?(Unquote) || x.is_a?(Module) || x == Any || x.primitive?)
            raise "Invalid pattern: #{x}"
          end
        end
      end
    end
  end
end

class Destruct
  module RuleSets
    class PatternBase
      include RuleSet

      def initialize
        add_rule(Ruby::VarRef) { |ref| Var.new(ref.name) }
        add_rule(Ruby::ConstRef) { |ref, binding:| binding.eval(ref.fqn) }
        add_rule_set(Ruby)
      end

      def validate(x)
        PatternValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'ast'

class Destruct
  module RuleSets
    class UnpackAst
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const lvar].freeze

      def initialize
        add_rule(Parser::AST::Node) do |n, transform:|
          raise Transformer::NotApplicable if ATOMIC_TYPES.include?(n.type)
          n.updated(nil, n.children.map(&transform))
        end
      end

      def m(type, *children)
        Parser::AST::Node.new(type, children)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class RubyInverse
      include RuleSet

      def initialize
        add_rule(Integer) { |value| n(:int, value) }
        add_rule(Symbol) { |value| n(:sym, value) }
        add_rule(Float) { |value| n(:float, value) }
        add_rule(String) { |value| n(:str, value) }
        add_rule(nil) { n(:nil) }
        add_rule(true) { n(:true) }
        add_rule(false) { n(:false) }
        add_rule(Array) { |items| n(:array, *items) }
        add_rule(Hash) { |h, transform:| n(:hash, *h.map { |k, v| n(:pair, transform.(k), transform.(v)) }) }
        add_rule(Module) { |m| m.name.split("::").map(&:to_sym).reduce(n(:cbase)) { |base, name| n(:const, base, name) } }
        add_rule_set(UnpackAst)
      end

      def n(type, *children)
        ::Parser::AST::Node.new(type, children)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
class Destruct
  module RuleSets
    class AstValidator
      class << self
        def validate(x)
          if x.is_a?(Parser::AST::Node)
            if !x.type.is_a?(Symbol)
              raise "Invalid pattern: #{x}"
            end
            x.children.each { |v| validate(v) }
          elsif !x.primitive?
            raise "Invalid pattern: #{x}"
          end
        end
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class Quote
      include RuleSet

      def initialize
        add_rule(->{ !expr }) do |raw_expr:, binding:|
          value = binding.eval(unparse(raw_expr))
          if value.is_a?(Parser::AST::Node)
            value
          else
            PatternInverse.transform(value)
          end
        end
        add_rule_set(UnpackAst)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class StandardPattern
      include RuleSet

      def initialize
        meta_rule_set AstToPattern
        add_rule(->{ strict(pat) }) { |pat:| Strict.new(pat) }
        add_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
        add_rule(->{ !expr }) { |expr:| Unquote.new(Transformer.unparse(expr)) }
        add_rule(->{ name <= pat }, name: Var) { |name:, pat:| Let.new(name.name, pat) }
        add_rule(-> { a | b }) { |a:, b:| Or.new(a, b) }
        add_rule(->{ klass[*field_pats] }, klass: [Class, Module], field_pats: [Var]) do |klass:, field_pats:|
          Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
        end
        add_rule(->{ klass[field_pats] }, klass: [Class, Module], field_pats: Hash) do |klass:, field_pats:|
          Obj.new(klass, field_pats)
        end
        add_rule(->{ is_a?(klass) }, klass: [Class, Module]) { |klass:| Obj.new(klass) }
        add_rule(->{ v }, v: [Var, Ruby::VarRef]) do |v:|
          raise Transformer::NotApplicable unless v.name == :_
          Any
        end
        add_rule_set(PatternBase)
      end

      def validate(x)
        PatternValidator.validate(x)
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true

require 'ast'

class Destruct
  module RuleSets
    class AstToPattern
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const lvar].freeze

      def initialize
        mvar = n(:send, [nil, v(:name)])
        lvar = n(:lvar, [v(:name)])
        add_rule(any(mvar, lvar)) do |name:|
          Var.new(name)
        end
        add_rule(n(:splat, [any(mvar, lvar)])) do |name:|
          Splat.new(name)
        end
        add_rule(Parser::AST::Node) do |node, transform:|
          n(node.type, node.children.map { |c| transform.(c) })
        end
      end
    end
  end
end
# require_glob 'destruct/**/*.rb'
# frozen_string_literal: true


class Destruct
  module RuleSets
    class PatternInverse
      include RuleSet

      def initialize
        add_rule(Var) { |var| n(:lvar, var.name) }
        add_rule_set(RubyInverse)
      end

      def n(type, *children)
        ::Parser::AST::Node.new(type, children)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
require_relative '/home/pwinton/git/destruct/lib/destruct_ext.so'
end

BOOT_CODE
nil
