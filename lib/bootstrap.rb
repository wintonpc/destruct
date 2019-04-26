# frozen_string_literal: true

require 'stringio'

require_relative './destruct/rbeautify'

class Bootstrap

  def self.compile(base_namespace, root_file_path, out_path)
    new.compile(base_namespace, root_file_path, out_path)
  end

  def compile(base_namespace, root_file_path, out_path)
    writeln "module #{base_namespace}"
    squash_file(root_file_path)
    writeln "end"
    code = (@monkeypatch ? @monkeypatch + "\n" : "") + op.string
    code = code.gsub(/:__([\w_]+)__/, ":__#{base_namespace.downcase}_\\1__")
    code = Destruct::RBeautify.beautify_string(code.lines).first
    code += <<~EOD
      $boot_code ||= {}
      $boot_code['#{base_namespace.downcase}'] = <<'BOOT_CODE'
      #{code}
      BOOT_CODE
      nil
    EOD
    puts code
    File.write(out_path + ".rb", code)
    iseq = RubyVM::InstructionSequence.compile_file(out_path + ".rb")
    # File.delete(out_path + ".rb")
    File.write(out_path, iseq.to_binary)
    puts "Wrote #{base_namespace} to #{out_path}"
  end

  private

  def squash_file(path)
    if File.basename(path, ".rb") == "monkeypatch"
      @monkeypatch = File.read(path)
    else
      path = File.expand_path(path)
      File.readlines(path).each do |line|
        if line =~ /^require_relative\s+["']([^"']+)["']/
          required_path = File.expand_path($1, File.dirname(path))
          squash_require(required_path, line)
        elsif line =~ /^require_glob\s+["']([^"']+)["']/
          Dir.glob(File.expand_path($1, File.dirname(path))).each do |path|
            squash_require(path, line)
          end
        else
          writeln line
        end
      end
    end
  end

  def squash_require(required_path, line)
    required_path = required_path.sub(/.rb$/, '')
    unless required_paths.include?(required_path)
      required_paths.push(required_path)
      required_path_rb = "#{required_path}.rb"
      required_path_so = "#{required_path}.so"
      if File.exists?(required_path_rb)
        writeln "# #{line}"
        squash_file(required_path_rb)
      elsif File.exists?(required_path_so)
        writeln "require_relative '#{required_path_so}'"
      else
        raise "Cannot find file to squash: #{required_path}"
      end
    end
  end

  def op
    @op ||= StringIO.new
  end

  def required_paths
    @required_paths ||= []
  end

  def writeln(*args)
    op.puts(*args)
  end
end

puts Bootstrap.compile("Boot1", "lib/destruct.rb", "boot1")
