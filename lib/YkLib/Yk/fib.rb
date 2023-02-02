#!/usr/bin/env ruby
#fib.rb


class Fib
	ToSelect = {}
	def self.spawn &bl
		Fib.new &bl
	end
	attr_reader :forked
	@@current = nil
	def self.current
		@@current
	end
	def initialize &bl
		@forked = true if !@@current
		@fiber = Fiber.new do
			bl.call
			self.class.selectIOEnd
		end
		prev = @@current
		@@current = self
		begin
			toResume = @fiber.resume
			p.green
			if toResume
				p
				toResume.doResume
				p
			end
		ensure
			@@current = prev
		end
		p.red
	end
	def setForked
		@forked = true
	end
	def self.selectIO io
		fid = current
		ToSelect[io] = fid
		if ToSelect.size == 0
			return
		end
		begin
			if !fid.forked
				fid.setForked
				p
				Fiber.yield
				p
			else
				res = IO.select ToSelect.keys
				if res && res[0].size > 0
					res[0].delete io
					if res[0].size > 0
						sio = res[0].shuffle[0]
						Fiber.yield ToSelect[sio]
					end
				end
			end
		ensure
			ToSelect.delete io
		end
#		p
	end
	def self.selectIOEnd
		if ToSelect.size == 0
			return
		end
		res = IO.select ToSelect.keys
		if res && res[0].size > 0
			sio = res[0].shuffle[0]
			Fiber.yield ToSelect[sio]
			p
		end
	end
	def doResume
		@@current = self
		toResume = @fiber.resume
		if toResume
			p
			toResume.doResume
			p
		end
	end
	SleepFib2Io = {}
	def self.sleep sec = nil
		r, w = IO.pipe
		if sec
			Thread.new do
				sleep sec
				if !w.closed?
					w.write "\n"
					w.flush
				end
			end
		end
		SleepFib2Io[current] = w 
		selectIO r
		SleepFib2Io.delete current
		r.close
		w.close
	end
	def self.read io, a1 = nil, a2 = nil, &bl
		if a1.is_a? String
			buff = a1
		elsif a2.is_a? String
			buff = a2
		end
		if a1.is_a? Integer
			sz = a1
		elsif a2.is_a? Integer
			sz = a2
		end
#		p io
		selectIO io
#		p buff
		begin
#			p
			buff ||= ""
			io.readpartial sz || 1024, buff
			if bl
				bl.call buff
			end
#			p buff
		rescue EOFError
#			p $!
			nil
		end
#		p
	end
	def self.get_line io
#		p
		buff = ""
		if !read io, buff
			return
		end
#		p buff
		buff.each_line do |ln|
			p
			yield ln
		end
	end
	
	def awake
		io = SleepFib2Io[self]
		if io
			io.write "\n"
			io.flush
		end
	end
	
	def self.pass
		current.sleep 0
	end
end


