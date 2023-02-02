

class Set
	include Enumerable
	def initialize (*a)
		if a.size == 1 && a[0].is_a?(Set)
			@hash = a[0].hash.clone
			return
		end
		@hash = Hash.new
		insert(*a)
	end
	def insert (*a)
		failed = true
		a.each do |e|
			if !@hash.key?(e)
				failed = false
				@hash[e] = true
			end
		end
		!failed
	end
	attr :hash, true
	def each
		@hash.each do |e, v|
			yield e
		end
	end
	def begin
		ret = nil
		each do |e|
			ret = e
			break
		end
		ret
	end
	def clone
		self.class.new(self)
	end
	def include? (a)
		@hash.key? a
	end
	def + (arg)
		clone.union! arg
	end
	def - (arg)
		clone.except! arg
	end
	def union! (arg)
		arg.each do |e|
			insert e
		end
		self
	end
	def except! (arg)
		arg.each do |e|
			delete e
		end
		self
	end
	def clear
		@hash.clear
	end
	def delete (k)
		@hash.delete k
	end
	def inspect
		res = "("
		s = true
		each do |e|
			res +=  (s ? "" : ",") + e.inspect
			s &&= false
		end
		res += ")"
		res
	end
	def to_a
		@hash.keys
	end
	def index a
		@hash.keys.index a
	end
	def to_set
		self
	end
	def == (arg)
        if arg.is_a? Array
            arg = arg.to_set
            @hash == arg._hash
        elsif arg.is_a? Set
            @hash == arg._hash
        end
    end
    def _hash
        @hash
	end
	def size
		@hash.size
	end
	def join (*args)
		@hash.keys.join(*args)
	end
end


class Array
	def to_set
		ret = Set.new
		each do |e|
			ret.insert e
		end
		ret
	end
end


class KeyedSet < Set
	include Enumerable
	def initialize (keyMethod)
		if keyMethod.is_a? KeyedSet
			super(self)
			@keyMethod = keyMethod.keyMethod
		else
			super()
			@keyMethod = keyMethod
		end
	end
	def callKey e
		if @keyMethod.is_a? Symbol
			e.method(@keyMethod).call
		elsif @keyMethod.is_a?(String) && @keyMethod[0..0] == "."
			eval("e" + @keyMethod)
		else
			@keyMethod.to_proc.call e
		end
	end
	def insert (*a)
		failed = true
		a.each do |e|
			if !@hash.key?(k = callKey(e))
				failed = false
				@hash[k] = e
			end
		end
		!failed
	end
	def [] (i)
		@hash[i]
	end
	def []= (i, a)
		if callKey(a) != i
			raise ArgumentError.new("key value is different")
		end
		@hash[i] = a
	end
	attr :hash, true
	def include? (a)
		@hash.key? callKey(a)
	end
	def delete (a)
		@hash.delete callKey(a)
	end
	def each
		@hash.values.each do |e|
			yield e
		end
	end
end


