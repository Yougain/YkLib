class RandLabel
	def self.create
		rand(100000000).to_s.intern
	end
end

class Enumerator
	class ExpectItem
		attr_reader :regexp, :label, :block, :binding
		def initialize this, expr, label, bl, bind
			@this = this
			@regexp = expr
			@label = label
			@block = bl
			@binding = bind
		end
		def match isFirst
			matched = @regexp && @binding.eval("#{@this.peek.inspect} =~ #{@regexp.inspect}")
			if matched
				@this.next
				if isFirst
					while true
						catch @label do
							@block.call
							nil
						end == @label or break
					end
				else
					throw @label, @label
				end
			end
			matched
		end
		def continue num = 1, &bl
			num.times do
				@this.expect true, &bl
			end
		end
	end
	class PararellItem < ExpectItem
		Item = Struct.new :regexp, :label, ;block, :binding
		def initialize this
			@this = this
			@items = []
		end
		def add expr, label, bl, bind
			@items.push Item.new(expr, label, bl, bind)
		end
		def match isFirst
			it = @items.find do |it|
				it.regexp && it.binding.eval("#{@this.peek.inspect} =~ #{it.regexp.inspect}")
			end
			if !it
				it = @items.find{_1.regexp.nil?}
			end
			if it
				cur = @this.peek
				@this.next
				if isFirst
					while true
						ret = catch @label do
							it.block.call cur
							nil
						end
						break if ret.nil?
						j = @items.find{|i| i.label == ret[0]}
						if j
							it = j
							cur = ret[1]
							next
						else
							break
						end
					end
				else
					throw @label, [it.label, cur]
				end
			end
			it
		end
	end
	def expect expr = nil, &bl
		if expr == true
			expr = nil
			cont = true
		end
		if !@eItems[-1].is_a? PararellItem
			@eItems.push ExpectItem.new(self, expr, RandLabel.create, bl, binding_of_caller)
			it = nil
			entity = ->{
				isFirst = true
				@eItems.reverse_each do |eItem|
					it = eItem.match isFirst
					break if it
					isFirst = false
				end
				if cont
					it = true
					cur = peek
					self.next
					bl.call cur
				end
			}
			begin
				if @eItems.size == 1
					begin
						while true
							entity.call
							self.next
						end
					rescue StopIteration
					end
				else
					entity.call
				end
			ensure
				@eItems.pop
			end
			it
		else
			@exprs[-1].add expr, RandLabel.create, bl, caller_binding
		end
	end
	def pararell
		@eItems.push PararellItem.new(self)
		begin
			yield
			if @eItems.size == 1
				begin
					while true
						match or self.next
					end
				rescue StopIteration
				end
			else
				match
			end
		ensure
			@eItems.pop
		end
	end
	def else &bl
		if @eItems[-1].is_a? PararellItem
			@exprs[-1].add nil, RandLabel.create, bl, caller_binding
		end
	end
end


#(e = lines.to_enum).expect /.../ do |ln|
#	e.expect /a/ do
#	
#	end
#	e.expect /b/ do
#
#
#	end&.continue 5 do
#		
#	end
#	e.pararell do
#		e.expect /c/ do
#		end
#		e.expect /d/ do
#		end
#		e.else do
#		end
#	end
#end


