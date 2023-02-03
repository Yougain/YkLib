
require "Yk/generator__"
require "Yk/misc_tz"


class Ranger
	class NInf
	end
	class Inf
	end
	def Inf.num
		self
	end
	def Inf.to_s
		return "Inf"
	end
	def NInf.to_s
		return "Ninf"
	end
	def Inf.<=> (arg)
		return 1
	end
	def Inf.< (arg)
		false
	end
	def Inf.<= (arg)
		arg == Inf
	end
	def Inf.> (arg)
		arg != Inf
	end
	def Inf.>= (arg)
		true
	end
	def Inf.+ (arg)
		if arg != NInf
			Inf
		else
			raise ArgumentError.new("undefined: Inf + NInf\n")
		end
	end
	def Inf.- (arg)
		if arg != Inf
			Inf
		else
			raise ArgumentError.new("undefined: Inf - Inf\n")
		end
	end
	def Inf.-@ (arg)
		NInf
	end
	def NInf.num
		self
	end
	def NInf.<=> (arg)
		return -1
	end
	def NInf.< (arg)
		arg != NInf
	end
	def NInf.<= (arg)
		true
	end
	def NInf.> (arg)
		false
	end
	def NInf.>= (arg)
		arg == NInf
	end
	def NInf.+ (arg)
		if arg == Inf
			raise ArgumentError.new("undefined: NInf + Inf\n")
		else
			NInf
		end
	end
	def NInf.- (arg)
		if arg != NInf
			NInf
		else
			raise ArgumentError.new("undefined: NInf - NInf\n")
		end
	end
	def NInf.-@ (arg)
		Inf
	end
	def NInf.coerce (other)
		[other, other - 1]
	end
	def Inf.coerce (other)
		[other, other + 1]
	end
	class RgElem
		attr :num, true
		attr :mode, true
		def initialize (fig, mode = true)
			if fig.is_a? RgElem
				@num = fig.num
				@mode = fig.mode
				return
			end
			@num = fig
			@mode = mode
		end
		def clone
			RgElem.new(self)
		end
		def inverse
			RgElem.new(@num, !@mode)
		end
		def <=> (arg)
			@num <=> arg.num
		end
		def < (arg)
			@num < arg.num
		end
		def > (arg)
			@num > arg.num
		end
		def <= (arg)
			@num <= arg.num
		end
		def >= (arg)
			@num >= arg.num
		end
		def == (arg)
			@num == arg.num
		end
		def RgElem.from (arg)
			return RgElem.new(arg, true), RgElem.new(Inf, false)
		end
		def RgElem.to (arg)
			return RgElem.new(NInf, true), RgElem.new(arg + 1, false)
		end
		def RgElem.get (arg)
			case arg
			when :all
				return RgElem.new(NInf, true), RgElem.new(Inf, false)
			when Integer
				return RgElem.new(arg, true), RgElem.new(arg + 1, false)
			when Range
				#if !arg.first.is_a? Integer
				#	raise ArgumentError.new("illeagal Range object, #{arg.first.inspect}\n")
				#end
				#if !arg.last.is_a? Integer
				#	raise ArgumentError.new("illeagal Range object\n")
				#end
				if arg.exclude_end?
					if arg.first < arg.last
						@start, @last = RgElem.new(arg.first, true), RgElem.new(arg.last, false)
					else
						#er arg
						raise ArgumentError.new("illeagal Range object\n")
					end
				else
					if arg.first <= arg.last
						@start, @last = RgElem.new(arg.first, true), RgElem.new(arg.last + 1, false)
					else
						raise ArgumentError.new("illeagal Range object\n")
					end
				end
			end
		end
	end
	attr :ranges
	def initialize (*args)
		@ranges = []
		def @ranges.inspect
			res = "["
			each_index do |i|
				e = self[i]
				fin = i == size - 1
				res += "#{e ? e.num : e.inspect}#{!fin ? (e.mode ? '=' : '-') : ""}"
			end
			res += "]"
		end
		add(*args)
#		if !arg.is_a? self.class
#			if arg
#				if arg.is_a? String
#					arg = arg.to_i
#				end
#				@ranges.push(*RgElem.get(arg))
#			end
#		else
#			arg.ranges.each do |r|
#				@ranges.push r.clone
#			end
#		end
	end
	def check
		#er @ranges
		if @ranges.size % 2 != 0
			STDERR.write "size error!\n"
			exit 1
		end
		@ranges.each2by1 do |a, b|
			if a.mode == b.mode
				STDERR.write "mode error! #{a.mode}, #{b.mode}\n"
				exit 1
			end
			if a.num >= b.num
				STDERR.write "number error! #{a.num} >= #{b.num}\n"
				exit 1
			end
		end
	end
	def add (*args)
		args.each do |arg|
			case arg
			when Ranger
				arg.eachRange do |r|
					__add(r)
				end
			else
				__add(arg)
			end
		end
	end
	def __add (arg)
		start, last = RgElem.get(arg)
		_add(start, last)
	end
	def _add (start, last)
		#er start, last do
		#	"add #{start.num}=#{last.num}"
		#end
		if @ranges.size == 0
			@ranges.clear
			@ranges.push start, last
			return
		end
		if start < @ranges[0]
			if last < @ranges[0]
				@ranges.unshift start, last
				return
			elsif last == @ranges[0]
				@ranges[0].num = start.num
				return
			else
				if @ranges[-1] <= last
					@ranges.clear
					@ranges.push start, last
					return
				end
				@ranges[0].num = start.num
			end
		else
			if @ranges[-1] <= last
				if @ranges[-1] < start
					@ranges.push start, last
					return
				elsif @ranges[-1] == start
					@ranges[-1].num = last.num
					return
				else
					if start == @ranges[0]
						@ranges.clear
						@ranges.push start, last
						return
					end
					@ranges[-1].num = last.num
					if @ranges[-2].num == NInf
						return
					else
						last.num = @ranges[-2].num + 1
						if last.num == @ranges[-1].num
							last.num = last.num - 1
						end
						if start.num >= last.num
							return
						end
					end
				end
			end
		end
		startPos = nil
		lastPos = nil
		(0 .. @ranges.size - 2).each do |i|
			if @ranges[i] <= start && start < @ranges[i + 1]
				startPos = i
			end
			if @ranges[i] <= last && last < @ranges[i + 1]
				lastPos = i
			end
		end
		merge start, startPos, last, lastPos
	end
	def merge (start, startPos, last, lastPos)
		#er start, startPos, last, lastPos do
		#	"#{start.num}@#{startPos}=#{last.num}@#{lastPos}"
		#end
		case [@ranges[startPos].mode, @ranges[lastPos].mode, startPos == lastPos]
		when [true, true, true]
			return
		when [false, false, true]
			if start != @ranges[startPos]
				@ranges.insert startPos + 1, start, last
			else
				@ranges[startPos].num = last.num
			end
		when [true, true, false]
			@ranges.slice!(startPos + 1 .. lastPos)
		when [true, false, false]
			@ranges[lastPos].num = last.num
			@ranges.slice!(startPos + 1 ... lastPos)
		when [false, true, false]
			if start != @ranges[startPos]
				if startPos + 1 != lastPos
					@ranges.slice!(startPos + 2 .. lastPos)
				end
				@ranges[startPos + 1].num = start.num
			else
				@ranges.slice!(startPos .. lastPos)
			end
		when [false, false, false]
			if start != @ranges[startPos]
				@ranges[startPos + 1].num = start.num
				@ranges[lastPos].num = last.num
				@ranges.slice!(startPos + 2 .. lastPos - 1)
			else
				@ranges[lastPos].num = last.num
				@ranges.slice!(startPos .. lastPos - 1)
			end
		end
	end
	def addFrom (arg)
		start, last = RgElem.from(arg)
		_add(start, last)
	end
	def addTo (arg)
		start, last = RgElem.to(arg)
		_add(start, last)
	end
	def delFrom (arg)
		start, last = RgElem.from(arg)
		_del(start, last)
	end
	def delTo (arg)
		start, last = RgElem.to(arg)
		_del(start, last)
	end
	def del (arg)
		start, last = RgElem.get(arg)
		_del(start, last)
	end
	def _del (start, last)
		#er start, last do
		#	"del #{start.num}-#{last.num}"
		#end
		if @ranges.size == 0
			return
		end
		if start < @ranges[0]
			if last < @ranges[0]
				return
			else
				if @ranges[-1] <= last
					@ranges.clear
					return
				end
				start = RgElem.new(@ranges[0])
			end
		else
			if @ranges[-1] <= last
				if @ranges[-1] <= start
					return
				else
					if start <= @ranges[0]
						@ranges.clear
						return
					end
					if @ranges[-2] < start
						@ranges[-1].num = start.num
						return
					elsif @ranges[-2] == start
						@ranges.pop
						@ranges.pop
						return
					end
					@ranges.pop
					@ranges.pop
					startPos = nil
			        (0 .. @ranges.size - 2).each do |i|
            			if @ranges[i] <= start && start.num <= @ranges[i + 1].num - 1
		        	        startPos = i
						end
        		    end
					if startPos
						last = @ranges[-1]
						lastPos = @ranges.size - 1
						exclude start, startPos, last, lastPos
						return
					else
						return
					end
				end
			end
		end
		startPos = nil
		lastPos = nil
		(0 .. @ranges.size - 2).each do |i|
			if @ranges[i] <= start && start.num <= @ranges[i + 1].num - 1
				startPos = i
			end
			if @ranges[i] <= last && last.num <= @ranges[i + 1].num - 1
				lastPos = i
			end
		end
		exclude start, startPos, last, lastPos
	end
	def exclude (start, startPos, last, lastPos)
		#er start, startPos, last, lastPos do
		#	"#{start.num}@#{startPos}-#{last.num}@#{lastPos}"
		#end
		case [@ranges[startPos].mode, @ranges[lastPos].mode, startPos == lastPos]
		when [true, true, true]
			if start == @ranges[startPos]
				@ranges[startPos].num = last.num
			else
				@ranges.insert startPos + 1, start.inverse, last.inverse
			end
		when [false, false, true]
		when [true, true, false]
			@ranges[lastPos].num = last.num
			if @ranges[startPos] == start
				@ranges.slice!(startPos .. lastPos - 1)
			else
				@ranges[startPos + 1].num = start.num
				@ranges.slice!(startPos + 2 .. lastPos - 1)
			end
		when [true, false, false]
			if @ranges[startPos] == start
				@ranges.slice!(startPos .. lastPos)
			else
				@ranges[startPos + 1].num = start.num
				@ranges.slice!(startPos + 2 .. lastPos)
			end
		when [false, true, false]
			@ranges[lastPos].num = last.num
			@ranges.slice! startPos + 1 .. lastPos - 1
		when [false, false, false]
			@ranges.slice! startPos + 1 .. lastPos
		end
	end
	def reverse!
		if @ranges.size == 0
			@ranges.push RgElem.new(NInf, true), RgElem.new(Inf, false)
			return
		end
		@ranges.each do |e|
			e.mode = !e.mode
		end
		if @ranges[0].num == NInf
			@ranges.slice!(0)
		else
			@ranges.unshift RgElem.new(NInf, true)
		end
		if @ranges[-1].num == Inf
			@ranges.slice!(-1)
		else
			@ranges.push RgElem.new(Inf, false)
		end
		self
	end
	def reverse
		clone.reverse!
	end
	def except! (arg)
		arg.ranges.each2 do |a, b|
			_del(a, b)
		end
		self
	end
	def except (arg)
		clone.except! arg
	end
	def union! (arg)
		arg.ranges.each2 do |a, b|
			_add(a, b)
		end
		self
	end
	def union (arg)
		clone.union!(arg)
	end
	def intersect! (arg)
		except! arg.clone.reverse!
		self
	end
	def intersect (arg)
		c = clone
		c.intersect!(arg)
	end
	def clone
		self.class.new(self)
	end
	def each
		@ranges.each2 do |a, b|
			if a.num == b.num - 1
				yield a.num
			else
				yield a.num .. b.num - 1
			end
		end
	end
	def eachRange
		@ranges.each2 do |a, b|
			yield a.num .. b.num - 1
		end
	end
	def rangeArr
		ret = []
		eachRange do |r|
			ret.push r
		end
		ret
	end
	def == (arg)
		if arg.is_a? Ranger
			rangeArr == arg.rangeArr
		elsif arg.is_a? Integer
			ra = rangeArr
			if ra.size == 1
				ra[0].first == arg && ra[0].first == ra[0].last
			else
				false
			end
		end
	end
	def include? (*args)
		c = clone
		args.each do |a|
			if a.is_a? Range
				a = Ranger.new(a)
			end
			c.union! a
		end
		self == c
	end
	def take (*args)
		ar = Ranger.new
		args.each do |e|
			case e
			when Ranger
				ar.union! e
			when Integer, Range
				ar.add e
			end
		end
		ar.delTo 0
		ret = self.class.new
		ret.clear
		if @ranges[0].num == NInf
			return ret
		end
		offset = 0
		ar.each__ :eachRange do |g|
			s, l = (+g).first, (+g).last
			s -= offset
			l -= offset
			bg = nil
			eachRange do |r|
				a, b = r.first, r.last
				bg == "a" && bg = a
				clause do
					if !bg
						if b - a >= s
							bg = a + s
							redo
						end
					else
						if b - a >= l
							ret.add bg .. a + l
							g.inc
							s, l = (+g).first, (+g).last
							s -= offset
							l -= offset
							bg = nil
							redo
						else
							ret.add bg .. b
							bg = "a"
						end
					end
					offset += b - a + 1
					s -= b - a + 1
					l -= b - a + 1
				end
			end
		end
		ret
	end
	def size
		sz = 0
		eachRange do |r|
			sz += r.last - r.first + 1
		end
		sz
	end
	def clear
		@ranges.clear
	end
end


