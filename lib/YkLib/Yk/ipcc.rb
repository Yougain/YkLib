#!/usr/bin/env ruby


require 'Yk/path_aux'
require 'Yk/ipv4adr'
#require 'path_aux'
#require 'socket'


class String
	ICONF = "/etc/ipcc.conf"
	RCONF = "/etc/resolv.conf"
	port = 53535
	srv = nil
	if ICONF.readable_file?
		ICONF.read_each_line do |ln|
			if((srv = ln.strip_comment) != "")
				cfile = ICONF
				if(srv =~ /:/)
					port = $'
					srv = $`
				end
				break;
			end
		end
	end
	if !srv && RCONF.readable_file?
		RCONF.read_each_line do |ln|
			arr = ln.strip_comment.split
			if(arr && arr[0] == "nameserver" && arr[1])
				cfile = ICONF
				srv = arr[1]
				break
			end
		end
	end
	if !srv
		cfile = "default setting"
		srv = "127.0.0.1"
	end
	sockaddr = nil
	begin
		sockaddr = Socket.sockaddr_in(port, srv)
	rescue SocketError
		STDERR.write "cannot create socket for #{srv}:#{port} (from #{ICONF})\n"
	end
	S = Socket.open(Socket::AF_INET, Socket::SOCK_DGRAM, 0) rescue nil
	S.connect(sockaddr) if S
	def to_ipcc
		ipadr = nil
		if self =~ /^(\d|[1-9]\d|[12]\d\d)\.(\d|[1-9]\d|[12]\d\d)\.(\d|[1-9]\d|[12]\d\d)\.(\d|[1-9]\d|[12]\d\d)$/
			if $1.to_i <= 255 && $2.to_i <= 255 && $3.to_i <= 255 && $4.to_i <= 255
				ipadr = self
			end
		end
		if !ipadr
			ipadr = to_ipadr
		end
		if !ipadr
			STDERR.write "cannot get ip address for #{self}\n"
			nil
		else
			sin_addr = ipadr.split(/\./).map{|e| e.to_i}.pack("CCCC")
			10.times do
				S.write sin_addr
				sret = IO.select [S], [], [], 0.1
				if sret && sret[0][0] == S
					buff = S.recv(6) rescue nil
					if buff && buff.size == 6 && buff[0..3] == sin_addr
						if buff[4] == 0 || buff[5] == 0
							return ""
						else
							return buff[4..5]
						end
					end
				end
			end
			nil
		end
	end
end


if __FILE__.normalize_path == $0.normalize_path
	print ARGV[0].to_ipcc, "\n" if ARGV[0]
end

