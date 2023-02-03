#!/usr/bin/env ruby


require 'binding_of_caller'


class Expector
	class End < Exception
	end
	def until c, &blk
#		p
		bnd = binding.of_caller(1)
		to_throw = Class.new(Exception).new
		begin
			@cmp_test_objs.unshift [c, to_throw, bnd]
			loop do
				begin
					if !@started
						@started = true
						@fiber.resume
					end
				rescue FiberError
#					p
					raise End
				end
#				p @current
				@cmp_test_objs.each do |e, t, b|
#					p [e, t, b]
#					p e === @current
#					p "/#{e}/ === \"#{@current}\""
#					p b.eval("/#{e}/ === \"#{@current}\"")
					if b.eval("#{e.inspect} === #{@current.inspect}")
#						p t
						@started = false
						raise t
					end
				end
				blk.call if blk
				@started = false
			end
		rescue to_throw.class
#			p
		ensure
			@cmp_test_objs.shift
		end
	end
	alias expect until
	def initialize y, &blk
		@cmp_test_objs = []
		if y.respond_to? :each
			y = y.method(:each)
		end
		@fiber = Fiber.new do
			y.call do |e|
				@current = e
				Fiber.yield
			end
		end
		begin
			blk.call self
		rescue End
#			p
		end
	end
end


if __FILE__ == $0

require 'Yk/path_aux'
require 'Yk/debug2'

a = ["abc", "def1", "", "abc", "def2", ""]

Expector.new a do |expt|
	loop do
		p
		expt.until /^\s*$/ do
			p
			expt.expect /abc/
			p
			expt.expect /def(\d+)/
			p $1
			print $1.ln
		end
		p
	end
	p
end

p

end
