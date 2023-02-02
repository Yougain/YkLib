

require "Yk/misc_tz"
require "Yk/path_aux"
require "Yk/generator__"
require "Yk/ranger"
require "resolv"
require "Yk/ipv4adr"
require "timeout"


def ip2int (ip)
	ret = 0
	ip.split(".").each do |e|
		ret = ret * 256 + e.to_i
	end
	ret
end


def int2ip (int)
	d1 = (0xff000000 & int) >> 24
	d2 = (0x00ff0000 & int) >> 16
	d3 = (0x0000ff00 & int) >> 8
	d4 = 0x000000ff & int
	"#{d1}.#{d2}.#{d3}.#{d4}"
end


def net2djb (expr)
	ret = []
	if expr !~ /\//
		return expr
	end
	net = $`
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


def iprange2nets (ipexpr)
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


class Intf
	class RangeIntf < Ranger
		def eachNet (addr, mask, excludeBcast = false)
			base = ip2int(addr) & ip2int(mask)
			limit = ip2int("255.255.255.255") - ip2int(mask)
			if limit <= 1
				rg = 0 .. limit
			else
				rg = excludeBcast ? (1 .. limit - 1) : (0 .. limit)
			end
			(intersect Ranger.new(rg)).eachRange do |r|
				f = int2ip(base + r.first)
				l = int2ip(base + r.last)
				if f != l
					yield "#{f}-#{l}"
				else
					yield f
				end
			end
		end
	end
	class RangeN < RangeIntf
		def initialize (addr, mask = nil)
			if addr.is_a? RangeN
				super addr
			else
				super ip2int(addr) & ~ip2int(mask)
			end
		end
	end
	
	class RangeNumSeed < RangeIntf
		def initialize (range = nil)
			if !range
				super :all
			else
				if range.is_a? String
					super()
					arr = range.split(/[\,\s]+/)
					arr.each do |e|
						if e =~ /\-/
							from = $`.strip
							to = $'.strip
							if from != ""
								if to != ""
									add from.to_i .. to.to_i
								else
									addFrom from.to_i
								end
							else
								if to != ""
									addTo to.to_i
								end
							end
						else
							add e.to_i
						end
					end
				else
					super
				end
			end
		end
	end

	class Bridge
		attr :intfNameList
		attr :intfObjs
		attr :intf, true
		@@intf2Bridge = Hash.new
		@@bridgeList = Hash.new
		@@intfName2Bridge = Hash.new
		def members
			intfObjs
		end
		def initialize (n)
			@name = n
			@intfNameList = []
			@intfObjs = []
			@@bridgeList[n] = self
		end
		def add (intfName)
			@intfNameList.push intfName
			@@intfName2Bridge[intfName] = self
		end
		def Bridge.getParentBridge (intfName)
			@@intfName2Bridge[intfName]
		end
		def Bridge.isBridge (n)
			@@bridgeList[n]
		end
		def addObj (intfObj)
			@intfObjs.push intfObj
		end
		def commitRange
			if !@commitRange
				@commitRange = true
				@intf.gates.each do |g, gt|
					noRange, hasRange = [], []
					@intfObjs.each do |intfObj|
						gate = intfObj.newgate gt
						if gate.rangeNumSeed == nil
							noRange.push gate
						else
							hasRange.push gate
						end
					end
					rg = RangeNumSeed.new
					hasRange.each do |e|
						rg.except! e.rangeNumSeed
					end
					noRange.each do |e|
						e.rangeNumSeed = rg
					end
				end
			end
		end
	end

	class Gate
		attr :name
		attr :intf
		attr :mask, true
		attr :p2p, true
		attr :addr, true
		attr :bcast, true
		attr :fullName
		attr :rangeNumSeed, true
		def isBridge?
			@intf.isBridge?
		end
		def isBridged?
			@intf.isMemberOfBridge?
		end
		def initialize (n, intf, fromFile = false)
			if !fromFile
				if !n.is_a? Gate
					if n == nil
						n = ""
					end
					@intf = intf
					@name = n
					ntmp = n == "" ? "" : ":#{n}"
					@fullName = @intf.name + ntmp
					if (tmp = "/etc/proxy_arp_subnet" / @fullName).readable_file?
						@rangeNumSeed = RangeNumSeed.new(tmp.read.strip_comment)
						@proxy_arp = true
					else
						@rangeNumSeed = nil
					end
					@bridgeMember = false
				else
					@intf = intf
					@name = n.name
					if @name == nil
						@name = ""
					end
					ntmp = @name == "" ? "" : ":#{@name}"
					@fullName = @intf.name + ntmp
					@mask = n.mask
					@bcast = n.bcast
					@p2p = n.p2p
					@addr = n.addr
					@bridgeMember = true
					if (tmp = "/etc/bridge_subnet" / @fullName).readable_file?
						@rangeNumSeed = RangeNumSeed.new(tmp.read.strip_comment)
					else
						@rangeNumSeed = nil
					end
				end
			else
				ifcfgFile, subnetFile = n, intf
				ifcfgFile.read_each_line do |ln|
					ln.strip_comment!
					case ln
					when /^IPADDR\=/
						@addr = $'
					when /^NETMASK\=/
						@mask = $'
					when /^BROARDCAST\=/
						@bcast = $'
					end
				end
				if !@addr
					raise Exception.new("IPADDR is missing in file:#{ifcfgFile}")
				end
				if !@mask
					ai = ip2int(@addr)
					if ai <= ip2int("127.255.255.255")
						@mask = "255.0.0.0"
					elsif ip2int("128.0.0.0") <= ai && ai <= ip2int("191.255.255.255")
						@mask = "255.255.0.0"
					else
						@mask = "255.255.255.0"
					end
				end
				if !@bcast
					@bcast = int2ip((ip2int(@addr) & ip2int(@mask)) + ((1 << 32) - 1) - ip2int(@mask))
				end
				if subnetFile && subnetFile.readable_file?
					@rangeNumSeed = RangeNumSeed.new(subnetFile.read)
					@proxy_arp = true
				end
			end
		end
		def nets
			if !@nets
				@nets = []
				if !@p2p
					if @rangeNumSeed
						(@rangeNumSeed.except RangeN.new(@addr, @mask)).eachNet(@addr, @mask, true) do |n|
							@nets.push n
						end
					else
						RangeN.new(@addr, @mask).reverse!.eachNet(@addr, @mask, true) do |n|
							@nets.push n
						end
					end
				else
					@nets.push @p2p
				end
			end
			@nets
		end
		def take *args
			if !@p2p
				if @rangeNumSeed
					r = @rangeNumSeed.except RangeN.new(@addr, @mask)
				else
					r = RangeN.new(0..~ip2int(@mask)).except RangeN.new(@addr, @mask)
				end
				r = r.take(*args)
				r.eachNet(@addr, @mask, true) do |n|
					yield n
				end
			else
				r = Ranger.new(ip2int(@p2p)).take(*args)
				r.eachRange do |e|
					if e.first == e.last
						yield int2ip(e.first)
					else
						yield "#{int2ip e.first}-#{int2ip e.last}"
					end
				end
			end
		end
		MaskList = []
		def simpleMask
			if MaskList.size == 0
				MaskList.unshift "0.0.0.0"
				32.times do |i|
					MaskList.unshift int2ip((1 << 32) - (1 << i))
				end
			end
			if !@simpleMask
				@simpleMask = 1 + MaskList.index(@mask)
			end
		end
		def bcast_available?
			if @bcast
				if @proxy_arp
					@rangeNumSeed.include? RangeN.new(@bcast, @mask)
				else
					true
				end
			else
				false
			end
		end
		def net
			if !@net
				@net = int2ip(ip2int(@addr) & ip2int(@mask)) + "/" + simpleMask.to_s 
			end
			@net
		end
		def network
			if !@network
				@network = int2ip(ip2int(@addr) & ip2int(@mask))
			end
			@network
		end
		def nets_with_mask
			if !@nets_with_mask
				@nets_with_mask = []
				nets.each do |n|
					iprange2nets(n).each do |e|
						@nets_with_mask.push e
					end
				end
			end
			@nets_with_mask
		end
		def nets_each_ip
			if !@nets_ips
				@nets_ips = []
				nets.each do |n|
					if n =~ /\-/
						(ip2int($`)..ip2int($')).each do |e|
							@nets_ips.push int2ip(e)
						end
					end
				end
			end
			@nets_ips.each do |e|
				yield e
			end
		end
		def gateway
			if !@gateway
				if @intf
	    			`/sbin/route -n`.each_line do |ln|
						n, @gateway, mask, x, x, x, x, dev  = ln.split
						if n =~ /^(default|0\.0\.0\.0)$/ && mask = "0.0.0.0" && dev == @intf.name
							break
						end
					end
				end
			end
			@gateway
        end
		def startI
			if !@startI
				@startI = ip2int(@addr) & ip2int(@mask)
			end
			@startI
		end
		def lastI
			if !@lastI
				@lastI = startI + ((1 << 32) - 1 - ip2int(@mask))
			end
			@lastI
		end
		def in_net? arg
			arg = ip2int(arg)
			startI <= arg && arg <= lastI
		end
    end 
	attr :bridge
	attr :rangeNum
	attr :name
	def isBridge?
		@isBridge
	end
	def physicals
		!@isBridge ? [self] : @isBridge.members
	end
	@@firstEthIP = nil
	@@proxies = []
	attr :mac
	def proxies
		if !@proxies
			@proxies = []
			@@proxies.each do |intf|
				if intf != self
					@proxies.push intf
				end
			end
		end
		@proxies
	end
	def initialize (n)
		if (f = "/proc/sys/net/ipv4/conf/#{n}/proxy_arp").exist?
			if `cat #{f}`.chomp.to_i == 1
				@@proxies.push self
			end
		end
		m = `cat /sys/class/net/#{n}/address`.chomp
		if m != ""
			@mac = m
		end
		@name = n
		@isBridge = false
		if @bridge = Bridge.getParentBridge(n)
			@bridge.addObj self
		else
			if tmp = Bridge.isBridge(n)
				@isBridge = tmp
				tmp.intf = self
			end
			@gates = {}
		end
	end
	def logical
		if bridge
			bridge.intf
		else
			self
		end
	end
	def gates
		if !@gates
			@gates = {}
			if @bridge
				@bridge.intf.gates.each_value do |g|
					newgate(g)
				end
			end
		end
		@gates
	end
	def newgate (n)
		if !n.is_a? Gate
			gates[n] ||= Gate.new(n, self)
		else
			gates[n.name] ||= Gate.new(n, self)
		end
	end
	def isEth?
		@name =~ /^eth\d+$/i
	end
	def net
		ret = []
		gates.each do |g|
			ret.push *g.net
		end
		ret
	end
	def isMemberOfBridge?
		@bridge != nil
	end
	def routes
		if !@routes
			@routes = []
			"/sbin/route -n".read_each_line_p do |ln|
				ln.strip_comment!
				arr = ln.split
				if arr[7] == @name
					@routes.push [arr[1], "#{arr[0]}/#{arr[2]}".to_maskbit]
				end
			end
		end
		@routes.each do |e|
			yield e[0], e[1]
		end
	end
	def Intf.getNewIntfs
		@@brList = Hash.new
		if "/usr/sbin/brctl".executable_file?
			IO.popen "/usr/sbin/brctl show" do |fr|
				fr.each__(:each_line) do |g|
					if +g =~ /^bridge\sname\s/
						next
					end
					if +g =~ /^Usage:/
						break
					end
					bridge = nil
					if +g =~ /^[^\s]+/
						bridge = @@brList[$&] = Bridge.new($&)
						if tmp = (+g).split[3]
							bridge.add tmp
							while g.next =~ /^\s+/
								g.inc
								bridge.add((+g).split[-1])
							end
						end
					end
				end
			end
		end
		@@intfs = Hash.new
		@@firstEthIP = nil
		IO.popen "/sbin/ifconfig" do |fr|
			intf = nil
			fr.each__(:each_line) do |g|
				if +g =~ /^[^\s]+/
					intfName = $&
					if intfName =~ /:/
						intfName = $`
						postFix = $'
					else
						postFix = ""
					end
					intf = (@@intfs[intfName] ||= Intf.new(intfName))
					if !intf.isMemberOfBridge?
						addr, mask, bcast, p2p = nil, nil, nil, nil
						while +g !~  /^\s*$/
							if +g =~ /inet addr:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
								intf != nil && addr = $1
								if !@@firstEthIP && intfName =~ /^eth\d+$/
									@@firstEthIP = addr
								end
							end
							if +g =~ /Mask:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
								intf != nil && mask = $1
							end
							if +g =~ /Bcast:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
								intf != nil && bcast = $1
							end
							if +g =~ /P\-t\-P:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
								intf != nil && p2p = $1
							end
							g.inc
						end
						if addr
							gate = intf.newgate(postFix)
							gate.addr, gate.mask, gate.bcast, gate.p2p = addr, mask, bcast, p2p
						end
					else
						while +g !~  /^\s*$/
							g.inc
						end
					end
				end
			end
		end
		@@gateList = {}
		@@intfs.each_value do |intf|
			intf.gates.each_value do |g|
				@@gateList[g.fullName] = g
			end
		end
		@@brList.each do |k, v|
			v.commitRange
		end
	end
	def Intf.gate (name, subnet = nil)
		if !defined? @@gateList
			getNewIntfs
		end
		if !(ret = @@gateList[name])
			if File.file?(name) && File.readable?(name)
				return Gate.new(name, subnet, true)
			end
		end
		ret
	end
	def Intf.gate_to (adr, direct = false)
		if !defined? @@gateList
            getNewIntfs
        end
		bridgeGates = []
		nonBridgeGates = []
		Intf.gates.each do |g|
			if g.isBridge?
				bridgeGates.push g
			else
				nonBridgeGates.push g
			end
		end
		gates = nonBridgeGates + bridgeGates
        if adr !~ /[\-|\/]/
			gates.each do |g|
				g.nets.each do |expr|
					if expr =~ /\-/
						if ip2int($`) <= (a = ip2int(adr)) && a <= ip2int($')
							if block_given?
								yield g, adr
								return
							else
								return g
							end
						end
					elsif expr == adr
						if block_given?
							yield g, adr
							return
						else
							return g
						end
					end
				end
			end
			if !direct
				"/sbin/route -n".read_each_line_p do |ln|
					tmp = ln.split
					if tmp.values_at(0, 2) == ["0.0.0.0", "0.0.0.0"]
						return Intf.gate_to(tmp[1])
					end
				end
			end
			return nil
		else
			rList = Hash.new
			gates.each do |g|
				g.nets.each do |expr|
					rList[g] =  IPRanger.new(adr.to_range).intersect IPRanger.new(expr.to_range)
				end
			end
			bridgeGates.each do |g|
				g.intf.bridge.intfObjs.each do |i|
					i.gates.values.each do |g2|
						if g2.name == g.name
							rList[g].del rList[g2]
						end
					end
				end
			end
			rList.each do |g, n|
				n.eachRange do
					yield g, n
				end
			end
		end
	end
	def Intf.gates
		if !defined? @@gateList
			getNewIntfs
		end
		@@gateList.values
	end
	def Intf.firstEthIP
		@@firstEthIP
	end
	def Intf.intfs
		if !defined? @@intfs
			getNewIntfs
		end
		@@intfs.values
	end
	def Intf.intf (n)
		if !defined? @@intfs
			getNewIntfs
		end
		@@intfs[n]
	end
	def Intf.hostIP
		resolver = Resolv::Hosts.new
		ip = resolver.getaddress(`hostname -s`.strip) rescue nil
		if ip != "127.0.0.1"
			return ip
		else
			return firstEthIP
		end
	end
	def Intf.gateway
		gw = "/etc/sysconfig/network".read[/\bGATEWAY\=([^\s]+)/, 1]
		if !gw
			if "/etc/crifcfg".exist?
				"/etc/crifcfg".each_entry do |f|
					if (f / "ifcfg").readable_file?
						gw = (f / "ifcfg").read[/\bGATEWAY\=([^\s]+)/, 1]
						break if gw
					end
				end
			end
			if !gw
				"/etc/sysconfig/network-scripts/ifcfg-*".glob do |f|
					if f.extname != ".bak" || f.extname != ".org"
						gw = f.read[/\bGATEWAY\=([^\s]+)/, 1]
						break if gw
					end
				end
			end
		end
		gw
	end
end

if $0 == __FILE__
	$DEBUG=1
	require "Yk/debugout"
	exit 1
	require 'Yk/auto_pstore'

	AutoPstore.rander ||= []
	#AutoPstore.rander.clear
	if AutoPstore.rander.size > 100
		AutoPstore.rander.clear
	end

	$i = 0

	def rander
		tmp = AutoPstore.rander
		ret = tmp[$i]
		if !ret
			AutoPstore.rander.push(ret = (rand * 10).to_i)
		end
		$i += 1
		ret
	end


	rgr = Ranger.new
	r = Proc.new do rander end
	rg = Proc.new do
		a = [nil, nil]
		while a[0] == a[1]
			a = [r.call, r.call].sort
		end
		a[0]..a[1]
	end
	100.times do
		rgr.reverse!
		rgr.check
		rgr.add(rg.call)
		rgr.check
		rgr.add r.call
		rgr.check
		rgr.del r.call
		rgr.check
		rgr.addFrom r.call
		rgr.check
		rgr.addTo r.call
		rgr.check
		rgr.delFrom r.call
		rgr.check
		rgr.delTo r.call
		rgr.check
		rgr.del(rg.call)
		rgr.check
	end
end


