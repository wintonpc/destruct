require 'memory_profiler'
require 'destructure'

describe 'Performance' do
  it 'is memory-efficient' do
    a = [1, 2, 3, 4]
    match_once(a)
    report = MemoryProfiler.report do
      1.times do
        match_once(a)
      end
    end

    report.pretty_print # at last check, this was allocating 288 bytes
  end

  it 'is time-efficient' do
    a = [1, 2, 3, 4]
    50_000.times.each { match_once(a) } # should take a fraction of a second
  end

  def match_once(a)
    destructure(a) do
      if match { [1, x, y, 4] }
      else
        raise "didn't match"
      end
    end
  end

  def match_once2(a)
    return nil unless a.size == 4
    return nil unless a[0] == 1
    return nil unless a[3] == 4
    env_keys = nil
    env_values = nil

    value = a[1]
    idx = env_keys && env_keys.find_index { |k| k == :x }
    if idx
      return nil unless env_values[idx] == value
    else
      env_keys ||= []
      env_values ||= []
      env_keys << :x
      env_values << value
    end

    value = a[2]
    idx = env_keys.find_index { |k| k == :y }
    if idx
      return nil unless env_values[idx] == value
    else
      env_keys << :y
      env_values << value
    end

    true
  end
end
