# frozen_string_literal: true

class TimeIt
  class << self
    Rec = Struct.new(:name, :parent, :start, :stop, :children, :multis, :multi_counts)
    Diff = Struct.new(:name, :duration, :children)

    def time_it(name, multi: false, disable_gc: false)
      GC.start if top_level?
      begin_rec(name)
      GC.disable if disable_gc
      start = Time.now
      yield
    ensure
      stop = Time.now
      end_rec(start, stop)
      GC.enable if top_level?
    end

    def time_all(name)
      name = "#{name}*"
      if top_level?
        yield
        raise 'time_all must be called within a time_it block'
      end
      start = Time.now
      yield
    ensure
      stop = Time.now
      if @rec
        @rec.multis[name] += duration2(start, stop)
        @rec.multi_counts[name] += 1
      end
    end

    def compare(rec1, rec2)
      diff = compare_recs([rec1], [rec2]).first
      report(diff, &method(:visit_diff))
    end

    def timing_now?
      !top_level?
    end

    private

    def compare_recs(as, bs)
      key = :name.to_proc
      outer_join(as, bs, key, key, nil, nil).map do |a, b|
        if a.nil?
          Diff.new(b.name, duration(b), [])
        elsif b.nil?
          Diff.new(a.name, -duration(a), [])
        else
          Diff.new(a.name, duration2(b.start - a.start, b.stop - a.stop), compare_recs(a.children, b.children) + compare_multis(a.multis, b.multis))
        end
      end
    end

    def compare_multis(as, bs)
      key = :first.to_proc
      outer_join(as, bs, key, key, nil, nil).map do |a, b|
        a_name, a_dur = a
        b_name, b_dur = b
        if a.nil?
          Diff.new(b_name, b_dur, [])
        elsif b.nil?
          Diff.new(a_name, -a_dur, [])
        else
          Diff.new(a_name, b_dur - a_dur, [])
        end
      end
    end

    def top_level?
      !@rec
    end

    def multi
      @multi ||= Hash.new(0)
    end

    def begin_rec(name)
      parent = @rec
      @rec = new_rec(name, parent)
      parent.children << @rec if parent
    end

    def new_rec(name, parent, start=-1, stop=-1)
      Rec.new(name, parent, start, stop, [], Hash.new(0), Hash.new(0))
    end

    def end_rec(start, stop)
      @rec.start = start
      @rec.stop  = stop
      rec = @rec
      @rec = @rec.parent
      if top_level?
        report(rec, &method(:visit_rec))
        ($time_it_recordings ||= []) << rec
        @multi = nil
      end
      rec
    end

    def report(rec_or_diff, &visitor)
      q = visitor.call(rec_or_diff) { |name, duration, depth, count| [format_name(name, depth, count), format_duration(duration)] }
      max_name_width = q.map(&:first).map(&:size).max
      max_time_width = q.map(&:last).map(&:size).max
      print_time_it(rec_or_diff, max_name_width, max_time_width, &visitor)
    end

    def format_duration(duration)
      duration.round.to_s
    end

    def visit_rec(r, depth=0, &visit)
      [
          visit.call(r.name, duration(r), depth, 1),
          *insert_mysteries(r.children).flat_map { |c| visit_rec(c, depth + 1, &visit) },
          *r.multis.map { |(name, duration)| visit.call(name, duration, depth + 1, r.multi_counts[name]) }
      ]
    end

    def visit_diff(d, depth=0, &visit)
      [
          visit.call(d.name, d.duration, depth, 1),
          *d.children.flat_map { |c| visit_diff(c, depth + 1, &visit) }
      ]
    end

    MYSTERY_NAME = '???'

    def insert_mysteries(tis)
      return [] if tis.none?
      parent = tis.first.parent
      [
          new_rec(MYSTERY_NAME, parent, parent.start, tis.first.start),
          *tis.drop(1).inject([tis.first]) do |acc, ti|
            acc << new_rec(MYSTERY_NAME, parent, acc.last.stop, ti.start)
            acc << ti
          end,
          new_rec(MYSTERY_NAME, parent, tis.last.stop, parent.stop)
      ]
    end

    def print_time_it(ti, max_name_width, max_time_width, &visitor)
      total_width = max_name_width + max_time_width + 7
      write('-' * total_width) if $time_it_pretty
      visitor.call(ti) do |name, duration, depth, count|
        if name == MYSTERY_NAME && duration.abs >= $time_it_mystery_threshold_ms
          write(cjust("#{format_name(name, depth)} ", " #{format_duration(duration)} ms", total_width, '.'))
        elsif name != MYSTERY_NAME && duration.abs >= $time_it_threshold_ms
          write(cjust("#{format_name(name, depth, count)} ", " #{format_duration(duration)} ms", total_width, '.'))
        end
      end
      write('-' * total_width) if $time_it_pretty
    end

    def write(s)
      $time_it_writer.call(s)
    end

    def cjust(left, right, width, char=' ')
      left + (char * (width - left.size - right.size)) + right
    end

    def duration(ti)
      duration2(ti.start, ti.stop)
    end

    def duration2(start, stop)
      (stop - start) * 1000
    end

    def format_name(name, depth, count=nil)
      "#{'  ' * depth}#{count ? name.sub(/\*$/, " (#{count}x)") : name}"
    end

    def outer_join(left, right, get_left_key, get_right_key, left_default, right_default)
      ls = left.each_with_object({}) { |x, h| h.store(get_left_key.call(x), x) }   # Avoid #hash_map and Array#to_h
      rs = right.each_with_object({}) { |x, h| h.store(get_right_key.call(x), x) } #   for better performance

      raise 'duplicate left keys' if ls.size < left.size
      raise 'duplicate right keys' if rs.size < right.size

      result = []

      ls.each_pair do |k, l|
        r = rs[k]
        if r
          rs.delete(k)
        else
          r = get_default(right_default, l)
        end
        result.push [l, r]
      end

      rs.each_pair do |_, r|
        result.push [get_default(left_default, r), r]
      end

      result
    end

    def get_default(default, other_side_value)
      default.callable? ? default.call(other_side_value) : default
    end
  end
end

def time_it(name, &block)
  if $time_it_enabled
    TimeIt.time_it(name, &block)
  else
    block.call
  end
end

def time_all(name, &block)
  if $time_it_enabled
    TimeIt.time_all(name, &block)
  else
    block.call
  end
end

def suspend_time_it
  oldval = $time_it_enabled
  $time_it_enabled = false
  yield
ensure
  $time_it_enabled = oldval
end

$time_it_threshold_ms = 0
$time_it_mystery_threshold_ms = 10
$time_it_writer = proc { |s| puts s }
$time_it_pretty = true
$time_it_enabled = true
