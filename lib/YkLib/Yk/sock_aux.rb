
require 'socket'
require 'Yk/__defun__'


class String
	def accept (&bl)
		if self =~ /:/
			args = [$`, $']
		else
			args = [self]
		end
		gs = TCPServer.open *args
		while true
			Thread.start(gs.accept) do |s|       # save to dynamic variable
				s.__defun__ :peer, "#{s.peeraddr[2]}:#{s.peeraddr[1]}"
				begin
					bl.call s
				ensure
					s.close
				end
			end
		end
	end
	def connect (sv = nil, &bl)
		if self =~ /:/
			host, service = $`, $'
		elsif sv
			host, service = self, sv
		else
			ArgumentError.new "cannot connect to #{self} : port not specified"
		end
		s = TCPSocket.open host, service
		begin
			yield s
		ensure
			s.close
		end
	end
end


