#!/usr/bin/env ruby
# some gertrude specific utility classes

class Utils
    # Seconds per minute
    SEC_PER_MIN = 60
    # Seconds per hour
    SEC_PER_HR = SEC_PER_MIN * 60
    # Seconds per day
    SEC_PER_DAY = SEC_PER_HR * 24
    # Seconds per week
    SEC_PER_WK = SEC_PER_DAY * 7
    # Seconds per (30-day) month
    SEC_PER_MNTH = SEC_PER_DAY * 30
    # Second per (non-leap) year
    SEC_PER_YR = SEC_PER_DAY * 365

    # Auxiliary method needed by Utils.secs_to_string
    def Utils.secs_to_string_case(array, var, string, plural)
      case var
      when 1
        array << "1 #{string}"
      else
        array << "#{var} #{plural}"
      end
    end

    # Turn a number of seconds into a human readable string, e.g
    # 2 days, 3 hours, 18 minutes and 10 seconds
    def Utils.secs_to_string(secs)
      ret = []
      years, secs = secs.divmod SEC_PER_YR
      secs_to_string_case(ret, years, "year", "years") if years > 0
      months, secs = secs.divmod SEC_PER_MNTH
      secs_to_string_case(ret, months, "month", "months") if months > 0
      days, secs = secs.divmod SEC_PER_DAY
      secs_to_string_case(ret, days, "day", "days") if days > 0
      hours, secs = secs.divmod SEC_PER_HR
      secs_to_string_case(ret, hours, "hour", "hours") if hours > 0
      mins, secs = secs.divmod SEC_PER_MIN
      secs_to_string_case(ret, mins, "minute", "minutes") if mins > 0
      secs = secs.to_i
      secs_to_string_case(ret, secs, "second", "seconds") if secs > 0 or ret.empty?
      case ret.length
      when 0
        raise "Empty ret array!"
      when 1
        return ret.to_s
      else
        return [ret[0, ret.length-1].join(", ") , ret[-1]].join(" and ")
      end
    end

    # Turn a number of seconds into a hours:minutes:seconds e.g.
    # 3:18:10 or 5'12" or 7s
    #
    def Utils.secs_to_short(seconds)
      secs = seconds.to_i # make sure it's an integer
      mins, secs = secs.divmod 60
      hours, mins = mins.divmod 60
      if hours > 0
        return ("%s:%s:%s" % [hours, mins, secs])
      elsif mins > 0
        return ("%s'%s\"" % [mins, secs])
      else
        return ("%ss" % [secs])
      end
    end

    # Returns human readable time.
    # Like: 5 days ago
    #       about one hour ago
    # options
    # :start_date, sets the time to measure against, defaults to now
    # :date_format, used with <tt>to_formatted_s<tt>, default to :default
    def Utils.timeago(time, options = {})
      start_date = options.delete(:start_date) || Time.new
      date_format = options.delete(:date_format) || "%x"
      delta = (start_date - time).round
      if delta.abs < 2
        "right now"
      else
        distance = Utils.age_string(delta)
        if delta < 0
          "%{d} from now" % {:d => distance}
        else
          "%{d} ago" % {:d => distance}
        end
      end
    end

    # Converts age in seconds to "nn units". Inspired by previous attempts
    # but also gitweb's age_string() sub
    def Utils.age_string(secs)
      case
      when secs < 0
        Utils.age_string(-secs)
      when secs > 2*SEC_PER_YR
        "%{m} years" % { :m => secs/SEC_PER_YR }
      when secs > 2*SEC_PER_MNTH
        "%{m} months" % { :m => secs/SEC_PER_MNTH }
      when secs > 2*SEC_PER_WK
        "%{m} weeks" % { :m => secs/SEC_PER_WK }
      when secs > 2*SEC_PER_DAY
        "%{m} days" % { :m => secs/SEC_PER_DAY }
      when secs > 2*SEC_PER_HR
        "%{m} hours" % { :m => secs/SEC_PER_HR }
      when (20*SEC_PER_MIN..40*SEC_PER_MIN).include?(secs)
        "half an hour"
      when (50*SEC_PER_MIN..70*SEC_PER_MIN).include?(secs)
        "an hour"
      when (80*SEC_PER_MIN..100*SEC_PER_MIN).include?(secs)
        "an hour and a half"
      when secs > 2*SEC_PER_MIN
        "%{m} minutes" % { :m => secs/SEC_PER_MIN }
      when secs > 1
        "%{m} seconds" % { :m => secs }
      else
        "one second"
      end
    end

end
