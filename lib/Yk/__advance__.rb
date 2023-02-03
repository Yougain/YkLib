#!/usr/bin/env ruby


require 'generator'
require 'delegate'
require 'Yk/__defun__'


class A__Advance__ < Exception
	def initialize (cc)
		@cc = cc
		super "advance"
	end
	def resume
		@cc.call
	end
end


def __advance__
	callcc do |cc|
		raise A__Advance__.new(cc)
	end
end

class Object
	def __adv__
		A__Adv__.new(self)
	end
end


class A__Adv__
	class DefunDelegator < Delegator
		def __defun__ (*arg, &proc)
			super
		end
		def __getobj__
			@target__
		end
		def __setobj__ (t)
			@target__ = t
		end
		def coerce (other)
			[other, @target__]
		end
	end
	def initialize (obj)
		@obj = obj
	end
	def __toAry__ (*args)
		args
	end
	def method_missing (itName, *args)
		ret = nil
		gen = Generator.new do |g|
			ret = @obj.method(itName).call(*args) do |*bag|
				g.yield *bag
			end
		end
		argsCue = nil
		proxies = nil
		pushCue = Proc.new do
			if gen.next?
				if argsCue == nil
					ag = __toAry__(*gen.next)
					argsCue = [ag]
					proxies = []
					ag.each_index do |i|
						e = ag[i]
						d = DefunDelegator.new(e)
						d.__defun__ :__next__, i do |no, *c|
							cnt = c[0]
							cnt ||= 1
							if cnt == 0
								proxies[no]
							else
								(cnt - argsCue.size).times do
									if !pushCue.call
										break
									end
								end
								if cnt <= argsCue.size
									argsCue[cnt - 1][no]
								end
							end
						end
						proxies.push d
					end
				else
					ag = __toAry__(*gen.next)
					argsCue.push ag
				end
				true
			else
				false
			end
		end
		setNext = Proc.new do
			if (argsCue == nil || argsCue.size == 0) && !pushCue.call
				false
			else
				proxies.each_index do |i|
					proxies[i].__setobj__(argsCue[0][i])
				end
				argsCue.shift
				true
			end
		end
		while true
			begin
				if setNext.call
					yield *proxies
				else
					break
				end
			rescue A__Advance__ => e
				if setNext.call
					e.resume
				else
					break
				end
			end
		end
		ret
	end
end


if File.expand_path(__FILE__) == File.expand_path($0)

arr = [1, 2, 3, 4, 5, 6, 7, 8]


arr.__adv__.each do |e|
	print "cur:#{e.inspect}, next:#{e.next.inspect}\n"
	if e == 4
		p "advancing: #{e}, less than 5: #{5 > e}"
		p "next: #{e.__next__},  less than 5: #{5 > e}"
		__advance__
		p "adcvanced: #{e}, less than 5: #{5 > e}"
	end
end

arr.__adv__.each do |e|
	__advance__
	p e
end


end
