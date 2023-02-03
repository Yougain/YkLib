#!/usr/bin/env ruby


class Object
	class Generator_
		def inc
            @cnt += 1
            if @nextIsEnd
                @current = nil
                @currentIsEnd = true
			#	@block.call
            else
              @current = @next
              begin
                @next = @enum.next
              rescue StopIteration
                @next = nil
                @nextIsEnd = true
              end
            end
            if @currentIsEnd
				if @fin
					@fin.call
				end
            end
			self
		end
		def next?
			!@nextIsEnd
		end
		def next
            if @nextIsEnd
                raise StopIteration
            end
			@next
		end
		def +@
            if @currentIsEnd
                raise StopIteration
            end
			@current
		end
		def current?
			!@currentIsEnd
		end
		def current
            if @currentIsEnd
              raise StopIteration
            end
			@current
		end
		def index
			@cnt
		end
		def initialize (m, args, fin = nil, &block)
			if !m.is_a? Method
				m = m.method(:each)
			end
			@block = block
            @cnt = 0
			@fin = fin
            @enum = m.receiver.to_enum #*args
            begin
              @current = @enum.next
            rescue StopIteration
              @currentIsEnd = true
              @nextIsEnd = true
              @fin.call if @fin
              return nil
            else
              @currentIsEnd = false
              begin
                @next = @enum.next
              rescue StopIteration
                @nextIsEnd = true
              else
                @nextIsEnd = false
              end
            end
            ret = nil
			if block
	            begin
    	          begin
            	    ret = block.call self
	              rescue StopIteration
    	            break
        	      end
            	  inc
	            end until @currentIsEnd
			end
			@fin = fin
            ret
		end
	end
	def each__ (mName = :each)
		m = self.method(mName)
		Generator_.new m, [] do |g|
			yield g
		end
	end
	def Object.generateEach (m, *args)
		Generator_.new m, args do |g|
			yield g
		end
	end
	def generator__ (mName = :each, &fin)
		m = self.method(mName)
		Generator_.new m, [], fin
	end
end


def generateEach__ (m, *args)
	Object.generateEach(m, *args) do |g|
		yield g
	end
end


#argv = []
#subArgs = Hash.new


#ARGV.each__ do |g|
#	if (+g)[0..1] == "--"
#		subArgNum = 0
#		switch = +g
#		case switch
#		when "--with1SubArg"
#			subArgNum = 2
#		end
#		subArgNum.times do
#			(subArgs[switch] ||= Array.new).push +g.inc
#		end
#	else
#		argv.push +g
#	end
#end


#p argv
#p subArgs


