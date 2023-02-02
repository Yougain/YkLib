
require 'Yk/debug2'
require 'Yk/sio'
require 'rb-inotify'


class String
	def wild_reg
		pre = ""
		all = "^"
		dbl_ast = nil
		i = 0
		each_char do |c|
			case c
			when "?"
				all += Regexp.escape pre
				pre = ""
				all += "[^\/]"
			when "*"
				if dbl_ast
					dbl_ast = false
					all += Regexp.escape pre
					pre = ""
					all += ".*?"
				else
					if self[i + 1] != "*"
						all += Regexp.escape pre
						pre = ""
						all += "[^\/]*?"
					else
						dbl_ast = true
						i += 1
						next
					end
				end
			else
				pre += c
			end
			i += 1
		end
		all += Regexp.escape pre
		Regexp.new(all + "$")
	end
	def on_filed &prc
		d, f = File.dirname(self), File.basename(self)
		raise Exception.new("Error: #{d} is not a existing dirctory.") if !d.directory?
		Inot[d].setParams f, prc
	end
	class Inot
		def setParams f, prc
			f = f.wild_reg if f =~ /\?|\*/
			@prcList.push [f, prc]
			self
		end
		def initialize d
			p :red, :init
			@prcList = []
			notifier = INotify::Notifier.new
			nio = notifier.to_io
			nio.set_sio
			notifier.watch d, :close_write, :moved_to do |ev|
				@prcList.each do |f, prc|
					prc.call d / ev.name if f === ev.name
				end
			end
			SIO.fork :auto_cleanup do
				loop do
					SIO.select nio.sio, :read
					notifier.process
				end
			end
		end
		List = Hash.new
		def self.[] d
			List[d] ||= Inot.new d
		end
	end
	def read_each_line_f
		
		
	end
end




