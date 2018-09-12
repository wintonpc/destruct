# frozen_string_literal: true

require 'stringio'

class Destruct
  module CodeGen
    GeneratedCode = Struct.new(:proc, :code, :filename)
    class GeneratedCode
      def inspect
        "#<GeneratedCode: #{filename}>"
      end
    end

    def emitted
      @emitted ||= StringIO.new
    end

    def emit(str)
      emitted << str
      emitted << "\n"
    end

    def generate(filename='')
      code = <<~CODE
        # frozen_string_literal: true
        lambda do |_code, _filename, _refs#{ref_args}|
          #{emitted.string}
        end
      CODE
      code = beautify_ruby(code)
      begin
        result = eval(code, nil, filename).call(code, filename, refs, *refs.values)
        gc = GeneratedCode.new(result, code, filename)
        show_code(gc) if $show_code
        gc
      rescue SyntaxError
        show_code(code, filename, refs, fancy: true, include_vm: false)
        raise
      end
    end

    def show_code_on_error
      emit_begin do
        yield
      end.rescue do
        emit "::Destruct::CodeGen.show_code(_code, _filename, _refs, fancy: false)"
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
      ", \n#{refs.map { |k, v| "#{k.to_s.ljust(8)}, # #{v.inspect}" }.join("\n")}\n"
    end

    def beautify_ruby(code)
      RBeautify.beautify_string(code.split("\n").reject { |line| line.strip == '' }).first
    end

    def refs
      @refs ||= {}
    end

    def reverse_refs
      @reverse_refs ||= {}
    end

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

    def get_temp(prefix="t")
      @temp_num ||= 0
      "_#{prefix}#{@temp_num += 1}"
    end

    module_function

    def show_code(code, filename="", refs=self.refs, fancy: true, include_vm: false, seen: [])
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
      lines = number_lines(code)
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

    def number_lines(code)
      code.split("\n").each_with_index.map do |line, n|
        "#{(n + 1).to_s.rjust(3)} #{line}"
      end
    end
  end
end
