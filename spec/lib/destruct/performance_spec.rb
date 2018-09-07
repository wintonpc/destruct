require 'memory_profiler'
require 'destruct'
require 'time_it'

class Destruct
  describe 'Performance' do
    let(:cp) { Destruct::Compiler.compile([1, Var.new(:x), Var.new(:y), 4]) }

    it 'is memory-efficient' do
      a = [1, 2, 3, 4]
      match_once(a)
      report = MemoryProfiler.report do
        1.times do
          match_once(a)
        end
      end

      report.pretty_print # at last check, this was allocating one 40 byte Env (appearing as <<Unknown>>)
    end

    it 'is time-efficient' do
      a = [1, 2, 3, 4]
      time_it("matches") { 100_000.times.each { match_once(a) } } # should take a fraction of a second
    end

    def match_once(a)
      p = cp
      p.match(a) or raise "didn't match"
    end
  end
end
