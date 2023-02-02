#


if ENV['DEBUG']
	$DEBUG = 1
end

require 'Yk/__defun__'

if ENV['DEBUG'] && ENV['DEBUG'] != "LOG"
	#require 'errlog'
end


class Errout
	FLines = Hash.new do |h, k|
		h[k] = IO.readlines(k)
	end
	def Errout.fReadLine (f)
		if f =~ /:/
			f = $`
			l = $'.to_i
		else
			l = f.to_i
			f = $PROGRAM_NAME
		end
		begin
			res = FLines[f][l - 1]
		rescue Errno::ENOENT
			res = ""
		end
	end
	def Errout.cutIn (s)
		if s =~ /:in.*/
			s =$`
		end
		s.sub(/^.\//, "")
		orgS = s
		if s =~ /:/
			if $` == $PROGRAM_NAME
				s = $'
			else
				s = File.basename($`) + ":" + $'
			end
		end
		s.__defun__ :orgdata do
			orgS
		end
		s
	end
	if ENV["DEBUG"] == "LOG"
		require 'syslog'
		def Errout.write (arg)
			Syslog.open if !Syslog.opened?
        	arg = arg.chomp
        	arg = arg.gsub /\n/, " "
        	arg = arg.gsub /\t/, " "
            i = 0
            cur = arg[i ... i + 80]
            while true
                if i != 0
                    body = "(__debug__errlog__) " + cur
                else
                    body = "(__debug__errlog__) (__d_first)" + cur
                end
                i += 80
                cur = arg[i ... i + 80]
                if cur
                    tail = "(__d_cont)\n"
                    Syslog.err body + tail
                else
                    tail = "\n"
                    Syslog.err body + tail
                   	break
                end
            end
        end
		def Errout.flush
		end
	else
		def Errout.write (arg)
			STDERR.write arg
		end
		def Errout.flush
			STDERR.flush
		end
	end
	def Errout.errout (strm, bl, *x)
		if !$DEBUG
			return
		end
		pos = caller(2)
		arr = []
		pos[0..3].each do |e|
			arr.push cutIn(e)
		end
		ln = fReadLine(arr[0].orgdata).strip
		ln.gsub! /\s+do$/, ""
		ln.gsub! /^er\s*/, ""
		ln.sub! /^\(/, ""
		ln.sub! /\)$/, ""
		larr = ln.split(/\s*\,\s*/)
		title = ""
		if x.size > 0 && x[0].is_a?(String) && (x[0] == larr[0])
			title = x.shift + (x.size > 0 ? ":" : "")
			larr.shift
		end
		ln = larr.join(', ')
		if x.size > 0
			if !bl
				s = [];x.each do |e| s.push e.inspect end; s = s.join(', ')
			else
				s = bl.call
			end
			toWrite = "#{title}#{ln}:#{s}|#{arr.join('|')}\n"
		else
			toWrite = "#{title}|#{arr.join('|')}\n"
		end
		if strm
			strm << toWrite
		else
			write toWrite
			flush
		end
	end
end


def er (*args, &bl)
	Errout.errout(nil, bl, *args)
end


def ero (*args, &bl)
	ret = ""
	Errout.errout(ret, bl, *args)
	ret.chomp!
end

