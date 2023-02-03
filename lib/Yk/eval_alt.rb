class String
	class LInfo
		attr_reader :fileName, :lno
		def initialize fName, lno
			@fileName = fName
			@lno = lno
		end
		def - op
			LInfo.new(@fileName, @lno - 1)
		end
		def > op
			@lno > op
		end
		def eql? arg
			@fileName == arg.fileName && @lno == arg.lno
		end
		def hash
			[@fileName, @lno].hash
		end
		def self.convLocations ret
			ret = ret.map do |e|
				file, lnum, funcPos = e.split /:/
				if file && lnum
					file, lnum = convLInfo file, lnum.to_i
					if funcPos
						[file, lnum, funcPos] * ":"
					else
						[file, lnum] * ":"
					end
				else
					e
				end
			end
			ret
		end
		InStrings = {}
		ConvList = {}
		FileLines = {}
		def self.convLInfo f, l
			k = LInfo.new(f, l)
			r = ConvList[k]
			if r
				[r.fileName, r.lno]
			else
				[f, l]
			end
		end
		def self.getFileLine f, ln
			FileLines[f] ||= IO.read(f).lines
			FileLines[f][ln - 1]
		end
	end
	def l?
		@orgPos
	end
	def l
		lc = count($/) + 1
		return if lc == 1
		f, lno_s, = caller(1)[0].split(/:/)
		linfo = LInfo.new(f, lno_s.to_i)
		if !@orgPos
			@orgPos = linfo
			cur = LInfo.new("//" + __id__.to_s, lc)
			while cur > 0
				LInfo::ConvList[cur] = linfo
				inStrings linfo do |linfo_in|
					cur -= 1
					LInfo::ConvList[cur] = linfo_in
				end
				cur -= 1
				linfo -= 1
			end
			if !LInfo::InStrings.empty?
				raise ArgumentError.new("Lined string is not cleared, or concatenated outside")
			end
		else
			LInfo::InStrings[linfo] = self
		end
		self
	end
	private
	def inStrings linfo
		in_string = LInfo::InStrings.delete linfo
		if in_string
			first = true
			in_string.each_line_info do |linfo_in|
				if !first
					yield linfo_in
				end
				first = false if first
			end
		end
	end
	protected
	def each_line_info
		linfo = LInfo.new("//" + __id__.to_s, count($/) + 1)
		while linfo > 0
			yield LInfo::ConvList[linfo]
			linfo -= 1
		end
	end
	public
	def each_line_with_info
		1.upto count($/) + 1 do |i|
			li = LInfo.new("//" + __id__.to_s, i)
			cv = LInfo::ConvList[li]
			t = cv || li
			f, ln = t.fileName, t.lno
			yield [f, ln] * ":" + " " + LInfo::getFileLine(f, ln).chomp + "/" + (lines[i - 1] ? lines[i - 1].chomp + "\n" : "\n")
		end
	end
	def getStartEnd
		self =~ /^\s+/
		start = $&.size
		self =~ /\s+$/
		ed = $&.size
		[start, size - ed - 1]
	end
end

class Module
	alias_method :__org_class_eval, :class_eval
	def class_eval expr = nil, fname = "(eval)", lno = 1, &bl
		prc =  Proc.new{ |e, f, lno, bl|
			e = __translate__ e, f, lno, bl, :class, self
			if bl
				__org_class_eval &bl if !e
			elsif e
				__org_class_eval e, f, lno
			end
		}
		if expr.respond_to?(:l?) && expr.l?
			prc.call expr, "//" + expr.__id__.to_s, 1
		else
			if expr && fname == "(eval)"
				fname, lno = binding.of_caller(1).source_location
			end
			prc.call expr, fname, lno, bl
		end
	end
	alias_method :__org_module_eval, :module_eval
	def module_eval expr = nil, fname = "(eval)", lno = 1, &bl
		prc =  Proc.new{ |e, f, lno, bl|
			e = __translate__ e, f, lno, bl, :module, self
			if bl
				__org_module_eval &bl if !e
			elsif e
				__org_module_eval e, f, lno
			end
		}
		if expr.respond_to?(:l?) && expr.l?
			prc.call expr, "//" + expr.__id__.to_s, 1
		else
			if expr && fname == "(eval)"
				fname, lno = binding.of_caller(1).source_location
			end
			prc.call expr, fname, lno, &bl
		end
	end
end

class BasicObject
	alias_method :__org_instance_eval, :instance_eval
	def instance_eval expr = nil, fname = "(eval)", lno = 1, &bl
		prc =  Proc.new{ |e, f, lno, bl|
			e = __translate__ e, f, lno, bl, :instance, self
			if bl
				__org_instance_eval f, lno, &bl if !e
			elsif e
				__org_instance_eval e, f, lno
			end
		}
		if expr.respond_to?(:l?) && expr.l?
			prc.call expr, "//" + expr.__id__.to_s, 1
		else
			if expr && fname == "(eval)"
				fname, lno = binding.of_caller(1).source_location
			end
			prc.call expr, fname, lno, bl
		end
	end
	private
	def __translate__ expr, f, lno, bl = nil, mode = :eval, this = nil
		expr
	end
end

class Thread::Backtrace::Location
end

module Kernel
	module_function
	alias_method :__org_eval, :eval
	def eval expr, b = nil, fname = "(eval)", lno = 1
		prc =  Proc.new{ |e, f, lno|
			e = __translate__ e, f, lno, nil, :eval, self
			__org_eval e, f, lno
		}
		if expr.l?
			prc.call expr, b, "//" + expr.__id__.to_s, 1
		else
			if fname == "(eval)"
				fname, lno = binding.of_caller(1).source_location
			end
			prc.call expr, b, fname, lno
		end
	end
	alias_method :__org_caller, :caller
	def caller (...)
		ret = __org_caller(...)
		ret.shift
		String::LInfo::convLocations ret
	end
	#alias_method :__org_caller_locations, :caller_locations
	#def caller_locations (...)
#		ret = __org_caller_locations(...)
		#ret.shift
		#String::LInfo::convLocations ret
	#end
end

class Exception
	alias_method :__org_backtrace, :backtrace
	@@last = []
	def backtrace
		#ret = __org_backtrace
		ret = caller
		if !ret.empty?
			@@last = String::LInfo::convLocations ret
		end
		@@last
	end
	alias_method :__org_message, :message
	def message
		ret = __org_message.clone
		ret.gsub! /(\/\/\d+):(\d+):/ do
			f, ln = String::LInfo::convLInfo $1, $2.to_i
			"#{f}:#{ln}"
		end
		ret
	end
end


class Binding
	alias_method :__org_eval, :eval
	def eval expr, fname = "(eval)", lno = 1
		prc =  Proc.new{ |e, f, lno|
			e = __translate__ e, f, lno, nil, :eval, self
			__org_eval e, f, lno
		}
		if expr.l?
			prc.call expr, expr.__id__.to_s, 1
		else
			if fname == "(eval)"
				fname, lno, = caller(1)[0].split(/:/)
			end
			prc.call expr, fname, lno.to_i
		end
	end
	alias_method :_org_source_location, :source_location
	def source_location
		f, ln = _org_source_location
		String::LInfo::convLInfo(f, ln)
	end
end


class Thread::Backtrace::Location
	alias_method :_org_lineno, :lineno
	alias_method :_org_path, :path
	def path
		f, l = String::LInfo::convLInfo(_org_path, _org_lineno)
		return f
	end
	def lineno
		f, l = String::LInfo::convLInfo(_org_path, _org_lineno)
		return l
	end
end

