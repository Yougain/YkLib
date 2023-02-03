

require "resolv"
require "Yk/ranger"


class Integer
	def to_ipadr
		d1 = (0xff000000 & self) >> 24
		d2 = (0x00ff0000 & self) >> 16
		d3 = (0x0000ff00 & self) >> 8
		d4 = 0x000000ff & self
		"#{d1}.#{d2}.#{d3}.#{d4}"
	end
	def to_mask
		if 0 <= self && self <= 32
			String::IPMaskList[self]
		else
			nil
		end
	end
end


class String
	IPMaskList = []
	33.times do |i|
		IPMaskList.unshift(((1 << 32) - (1 << i)).to_ipadr)
	end
	def __getMaskInfo
		adr = self
		if adr =~ /^\d|[1-9]\d$/ && adr.to_i <= 32
			[IPMaskList[adr.to_i], adr.to_i]
		elsif i = IPMaskList.index(adr)
			[adr, i]
		else
			nil
		end
	end
	def ipmask?
		if self =~ /^(\d|[1-9]\d)$/ && self.__org__to_i___ <= 32
			return true
		elsif IPMaskList.include? self
			return true
		end
		return false
	end
	def to_mask
		if ipmask?
			if self =~ /\./
				self.clone
			else
				IPMaskList[self.__org__to_i___]
			end
		elsif self =~ /\// && $`.ipadr? && $'.ipmask?
			$` + "/" + $'.to_mask
		else
			nil
		end
	end
	def to_maskbit
		if ipmask?
			if self =~ /\./
				IPMaskList.index self
			else
				self.__org__to_i___
			end
		elsif self =~ /\//
			if $`.ipadr? && $'.ipmask?
				$` + "/" + $'.to_maskbit.to_s
			else
				nil
			end
		else
			nil
		end
	end
	def ipadr?
		if self =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/
			(1..4).each do |i|
				a = $~[i].to_i
				a > 255 and return(false)
			end
			true
		else
			false
		end
	end
	def ipexpr?
		if !ipadr?
			if self !~ /\-/ || !$`.ipadr? || !$'.ipadr?
				if self !~ /\// || !$`.ipadr? || !$'.ipmask?
					return false
				end
			end
		end
		return true
	end
	def to_nets
		if !ipexpr?
			return nil
		end
		ipexpr = self
		if ipexpr !~ /\-/
			[ipexpr]
		else
			possibleMask = Proc.new do |i|
				j2 = nil
				32.times do |j|
					if i & (1 << j) != 0
						j2 = j
						break
					end
				end
				j2
			end
			ret = []
			arr = ipexpr.split /\-/
			bg = ip2int(arr[0].strip)
			ed = ip2int(arr[1].strip)
			while bg <= ed
				bgNext = nil
				possibleMask.call(bg).downto 0 do |m|
					if (bgNext = bg + (1 << m) - 1) <= ed
						bgNext += 1
						if m != 0
							ret.push "#{int2ip bg}/#{32 - m}"
						else
							ret.push int2ip(bg)
						end
						break
					end
				end
				bg = bgNext
			end
			ret
		end
	end
	def to_djbs
		ret = []
		expr = self
		if expr !~ /\//
			if expr =~ /\-/
				to_nets.each do |expr|
					ret.push *expr.to_djbs
				end
			end
		end
		net = $`
		if net.ipaddr?
			
		end
		mask = $'.to_i
		case mask
		when 25..32
			base = (ip2int(net) >> (32 - mask)) << (32 - mask)
			(0 ... 1 << (32 -mask)).each do |i|
				ret.push int2ip(base + i)
			end
		when 24
			net =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3})\./
			ret.push $1
		when 17..23
			base = (ip2int(net) >> (32 - mask)) << (24 - mask)
			(0 ... 1 << (24 -mask)).each do |i|
				ret.push int2ip((base + i) << 8)[/^(\d{1,3}\.\d{1,3}.\d{1,3})\./, 1]
			end
		when 16
			net =~ /^(\d{1,3}\.\d{1,3})\./
			ret.push $1
		when 9..15
			base = (ip2int(net) >> (32 - mask)) << (16 - mask)
			(0 ... 1 << (16 -mask)).each do |i|
				ret.push int2ip((base + i) << 16)[/^(\d{1,3}\.\d{1,3})\./, 1]
			end
		when 8
			net =~ /^(\d{1,3})\./
			ret.push $1
		when 0..7
			base = (ip2int(net) >> (32 - mask)) << (8 - mask)
			(0 ... 1 << (8 -mask)).each do |i|
				ret.push((base + i).to_s)
			end
		end
		ret
	end
	def to_range
		if ipadr?
			a = __ip2int
			return a .. a
		elsif self =~ /\-/ && $`.ipadr? && $'.ipadr?
			a = $'.__ip2int
			b = $`.__ip2int
			if a < b
				return a .. b
			elsif a > b
				return b .. a
			else
				return a .. a
			end
		elsif self =~ /\// && $`.ipadr? && m = $'.__getMaskInfo
			st = $`.__ip2int & m[0].__ip2int
			ed = st + (1 << (32 - m[1])) - 1
			return st .. ed
		else
			nil
		end
	end
	def __ip2int
		ret = 0
		self.split(".").each do |e|
			ret = ret * 256 + e.to_i
		end
		ret
	end
	alias_method :__org__to_i___, :to_i
	def to_i base = 10
		if ipadr?
			__ip2int
		else
			__org__to_i___ base
		end
	end
	RESOLVERS = Hash.new{|h, k| h[k] = Resolv::DNS.new(:nameserver => [k])}
	HOST_RESOLVER = Resolv::Hosts.new
	def to_ipadr server = nil
		if !ipexpr?
			ip2 = nil
			resolver = nil
			if server && (server = server.to_ipadr)
				resolver = RESOLVERS[server]
			else
				resolver = Resolv
			end
			[HOST_RESOLVER, resolver].each do |r|
				r.each_address(self) do |adr|
					adr = adr.to_s
					if !ip2
					   	ip2 = adr.to_i
					elsif ip2 < (ip3 = adr.to_i)
					    ip2 = ip3
					end
				end
				break if ip2
			end
			ip2.to_ipadr
		else
			self
		end
	end
	def to_ranger
		IPRanger.new self
	end
	def each_ip
		r = to_range
		r.each do |i|
			yield i.to_ipadr
		end
	end
end


class IPRanger < Ranger
	def initialize (*args)
		super()
		add *args
	end
	def inspect
		ns = []
		eachNetRange do |n|
			ns.push n
		end
		"[" + ns.join(",") + "]"
	end
	def modargs (*args)
		nargs = []
		args.each do |a|
			if a.is_a? String
				if tmp = a.to_range
					nargs.push tmp
				else
					nargs.push a.to_ipadr.to_range rescue next
				end
			elsif a.is_a? Ranger
				a.eachRange do |e|
					nargs.push e
				end
			else
				nargs.push a
			end
		end
		nargs
	end
	def add (*args)
		super *modargs(*args)
	end
	def del (*args)
		super *modargs(*args)
	end
	def include? (*args)
		super *modargs(*args)
	end
	def eachNetRange
		each do |e|
			if e.is_a? Range
				if e.exclude_end?
					yield e.first.to_ipadr + "-" + (e.last - 1).to_ipadr
				else
					yield e.first.to_ipadr + "-" + e.last.to_ipadr
				end
			else
				yield e.to_ipadr
			end
		end
	end
end


