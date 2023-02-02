#!/usr/bin/env ruby


require 'Yk/path_aux'
require 'Yk/auto_pstore'
require 'Yk/bsearch'
require 'Yk/ipv4adr'
require 'timeout'

module IPCountry

IPListURLs = %w{
					ftp://ftp.ripe.net/pub/stats/apnic/delegated-apnic-latest
					ftp://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest
					ftp://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-latest
					ftp://ftp.ripe.net/ripe/stats/delegated-ripencc-latest
					ftp://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-latest
				}


class IPInfo
	attr :country, true
	attr :start, true
	attr :ed, true
	attr :nxt, true
	def initialize c, s, e, n = nil
		@country = c
		if c == ""
			@country = "  "
		end
		@start = s
		@ed = e
		@nxt = n
	end
	def inspect
		[@country, @start.to_ipadr, @start].inspect
	end
end


class AllocList < Array
	attr :date
	def refresh
		tmp = []
		IPListURLs.each do |u|
			u.timeout = 3600 * 12
		end
		IPListURLs.each do |u|
			u.read_each_line do |ln|
				arr = ln.split /\|/
				if arr[2] == "ipv4" && arr[1] != "*" && arr[1] != ""
					tmp.push IPInfo.new(arr[1], arr[3].to_i, arr[3].to_i + arr[4].to_i)
				end
			end
		end
		tmp = tmp.sort_by do |a|
			a.start
		end
		tmp2 = []
		(0..tmp.size - 2).each do |i|
			if tmp[i].country == tmp[i + 1].country && tmp[i].ed == tmp[i + 1].start
				tmp[i + 1].start = tmp[i].start
				next
			end
			tmp[i].nxt = tmp[i + 1].start
			tmp2.push tmp[i]
		end
		tmp = tmp2
		tmp[-1].nxt = tmp[-1].ed
		clear
		tmp.each do |e|
			push e
		end
		("/var/data".check_dir / "ipcountry").open "w" do |fw|
			(0..tmp.size - 2).each do |i|
				if tmp[i].start >= tmp[i].ed
					next
				end
				if i == 0 && tmp[i].start != 0
					fw.write([0, 0, 0, 0, 0].pack("ICCCC"))
				end
				fw.write([tmp[i].start, tmp[i].country[0..0], tmp[i].country[1..1], 0, 0].pack("IAACC"))
				if tmp[i].ed < tmp[i + 1].start
					fw.write([tmp[i].ed, 0, 0, 0, 0].pack("ICCCC"))
				elsif tmp[i].ed > tmp[i + 1].start
					tmp[i + 1].start = tmp[i].ed
					STDERR.write "error #{tmp[i].country}:#{tmp[i].start.to_ipadr}-#{tmp[i].ed.to_ipadr}, #{tmp[i + 1].country}:#{tmp[i + 1].start.to_ipadr}-#{tmp[i + 1].ed.to_ipadr}\n"
				end
				if i == tmp.size - 2
					fw.write([tmp[i + 1].start, tmp[i + 1].country[0..0], tmp[i + 1].country[1..1], 0, 0].pack("IAACC"))
					if tmp[i + 1].ed != 0
						fw.write([tmp[i + 1].ed, 0, 0, 0, 0].pack("ICCCC"))
					end
				end
			end
		end
		@date = Time.now
	end
	def initialize
		refresh
	end
	def getCountry ipi
		if ipi < self[0].start || self[-1].ed < ipi
			return nil
		end
		fst = bsearch_first do |e|
			if ipi < e.start
				1
			elsif ipi < e.nxt
				0
			else
				-1
			end
		end
		if fst
			fst = self[fst]
			if ipi < fst.ed
				return fst.country
			else
				return nil
			end
		else
			return nil
		end
	end
end

end #module IPCountry


if $0 == __FILE__

if ARGV.delete "--refreshdb"
	AList = AutoPstore.allocList = IPCountry::AllocList.new
	exit 0
else
	AList = AutoPstore.setReadOnly.allocList || (AutoPstore.allocList = IPCountry::AllocList.new)
end


longFormat = ARGV.delete "-l"


if ARGV[0]
	if a = ARGV[0].to_ipadr
		if ret = AList.getCountry(a.to_i)
			if longFormat
				println "#{ret} : " + "ccode #{ret}".read_p
			else
				println ret
			end
			exit 0
		else
			STDERR.println "'#{ARGV[0]}' is not allocated"
			if STDIN.tty?
				print "\n"
			end
			exit 1
		end
	end
else
	STDERR.write "usage : ipcountry HOST\n        ipcountry --refreshdb (for refreshing its database)\n"
	exit 1
end

else
	require 'thread'
	module IPCountry
		@@mutex = Mutex.new
		def refresh
			@@mutex.synchronize do
				@@list = AutoPstore.readTemp.allocList
			end
		end
		def getCountry ip
			@@mutex.synchronize do
				@@list ||= AutoPstore.readTemp.allocList
				@@list.getCountry(ip.to_i)
			end
		end
		module_function :refresh, :getCountry
	end
	AutoPstore.setFileName "ipcountry"
	IPCountry::List = AutoPstore.readTemp.allocList
	class String
		def ipcountry is_cc = false
			TopLevelMethod.timeout 5 do
				if ip = to_ipadr
					if cc = IPCountry::getCountry(ip)
						if is_cc
							if cc == is_cc
								return cc
							end
						else
							return cc
						end
					else
						return nil
					end
				else
					return nil
				end
			end
		end
	end
end

