#!/usr/bin/env ruby


require 'delegate'

class MaxMin
	def initialize (item = nil)
		@item = item
	end
	def min= (item)
		if item != nil
			if @item != nil
				if @item > item
					@item = item
				end
			else
				@item = item
			end
		end
	end
	def max= (item)
		if item != nil
			if @item != nil
				if @item < item
					@item = item
				end
			else
				@item = item
			end
		end
	end
	def min
		@item
	end
	def max
		@item
	end
	def self.[] (a, b)
		if a < b
			[b, a]
		else
			[a, b]
		end
	end
end


class MinMax < MaxMin
	def self.[] (a, b)
		if a > b
			[b, a]
		else
			[a, b]
		end
	end
end

class MinMax__ < Delegator
	def initialize (arg = nil)
		if arg != nil
			super arg
			@__inited__ = true
			__setobj__(arg)
		else
			@__inited__ = false
		end
	end
	def __getobj__
		@__obj__
	end
	def __setobj__ (arg)
		@__obj__ = arg
	end
	def __min__= (arg)
		if arg == nil
			return self
		end
		if !@__inited__
			initialize(arg)
		elsif arg < self
			__setobj__(arg)
		end
		self
	end
	def __max__= (arg)
		if arg == nil
			return self
		end
		if !@__inited__
			initialize(arg)
		elsif arg > self
			__setobj__(arg)
		end
		self
	end
	def __min__
		@__obj__
	end
	def __max__
		@__obj__
	end
	def __obj__
		@__obj__
	end
	def coerce (other)
		[other, @__obj__]
	end
end


if __FILE__ == $PROGRAM_NAME
	t = MinMax__.new
	t.__min__ = 1
	t.__min__ = -1
	p t
	t2 = MinMax__.new
	t2.__max__ = "abc"
	t2.__max__ = "a"
	t2.__max__ = "z"
	p t2
end


