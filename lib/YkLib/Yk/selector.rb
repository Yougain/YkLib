

require 'set'

module SelectorFunc
	def set_selector s
		@selectors ||= Set.new
		@selectors.add s
	end
	def selectors
		@selectors
	end
end


class Selector
	def self.select &bl
		s = new
		if bl
			bl.call s
			s.select
		else
			s
		end
	end
	def initialize
		@readProcs = {}
		@writeBuffs = Hash.new{|h, k| h[k] = []}
		@writeFinals = {}
		@intReader, @intWriter = IO.pipe
	end
	def at_read fr, &bl
		@readProcs[fr] = bl
		if !fr.respond_to? :set_selector
			fr.extend SelectorFunc
		end
		fr.set_selector self
	end
	def int
		@intWriter.close
	end
	def reserve_write fp, buff
		if buff
			@writeBuffs[fp].push buff if buff != ""
		else
			@writeFinals[fp] = true
		end
	end
	def select
		selectable = true
		while selectable
			selectable = false
			reads = (@readProcs.keys + [@intReader]).select{|s| !s.closed?}
			writes = @writeBuffs.keys.select{|s| ((@writeBuffs[s] && @writeBuffs[s].size > 0) || @writeFinals[s]) && !s.closed?}
			break if reads.size + writes.size == 0
			begin
				selected, wselected = IO.select(reads, writes)
			rescue Errno::EIO
			rescue Errno::EBADF
			rescue IOError
			end
			selected.each do |fp|
				if fp != @intReader
					buff = ""
					begin
						buff = fp.readpartial 1024
					rescue EOFError => e
					rescue Errno::EIO
					rescue Errno::EBADF
					rescue IOError
					end
					if buff != ""
						@readProcs[fp].call buff
					end
					if fp.closed?
						@readProcs[fp].call ""
						@readProcs.delete fp
						next
					end
					#closed = true if buff == ""
					#@readProcs[fp].call buff
					#if closed
					#	@readProcs.delete fp
					#end
				else
					reads.each do |fz|
						if fz != fp && fz.closed?
							@readProcs[fz].call ""
						end
					end
					@intReader.close
					break
				end
			end
			wselected.each do |fp|
				buffs = @writeBuffs[fp]
				if buffs.size > 0
					buff = buffs[0]
					sz = fp.write buff
					fp.flush
					if sz < buff.size
						buff.replace buff[sz ... buff.size]
						break
					else
						buff.replace ""
						buffs.shift
					end
				end
				if (!buffs || buffs.size == 0) && @writeFinals[fp]
					@writeFinals.delete fp
					@writeBuffs.delete fp
					if ![STDERR, STDOUT].include? fp
						fp.close_write
					end
				end	
			end
			reads = reads.select{|s| !s.closed?}
			writes = @writeBuffs.keys.select{|s| !s.closed?}
			selectable = (reads - [STDIN]).size + (writes - [STDERR, STDOUT]).size > 0
		end
	end
end


