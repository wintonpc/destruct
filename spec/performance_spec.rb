require 'memory_profiler'
require 'destructure'

describe 'Performance' do
  it 'should be decent' do
    a = [1, 2, 3, 4]
    match_once = proc do
      destructure(a) do
        if match { [1, x, y, 4] }
        else
          raise "didn't match"
        end
      end
    end
    match_once.()
    report = MemoryProfiler.report do
      100.times do
        match_once.()
      end
    end

    report.pretty_print
  end
end
