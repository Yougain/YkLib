

require "Yk/pg_setup.rb"
require "Yk/with.rb"
using With

SQLExecMethod = %W{insert sort_by each select clear delete}

module SQLTableDefine
	class Error < Exception; end
	class SentenceContext < BasicObject
		ABC = 0
		attr_reader :sentence
		def sum ag
		end
		def initialize &prc
			#@sentence = With(self, &prc)
		end
		def __where__
			Where.new self
		end
		def __select__
			Select.new self
		end
		def __isCondition__?
		end
		def __isSelection__?
		end
	end
	private
	def check_init
		begin
			yield
		rescue
			if !@__col_type__
				@__col_type__ = {}
				@__def_val__ = {}
				@__check_proc__ = []
				@__is_key__ = {}
				@__is_unique__ = {}
				@__is_not_null__ = {}
				@__reference__ = {}
				retry
			end
		end
	end
	class Column
		attr_reader :label, :reference
		def initialize label, parent
			@label = label
			@parent = parent
		end
		def references rcol
			@parent.set_reference @label, rcol
		end
	end
	public
	def set_reference l, rc
		@__reference__[l] = rc
	end
	private
	def check_col_obj label
		if defined? label
			raise NameError.new("#{label} is already defined")
		else
			instance_variable_set("@#{label}", Column.new(label, self))
			attr_reader label
		end
	end
	
	class DefColHelperBase
		def initialize l, c
			@toHelp = c
			@type = l
		end
	end
	class DefColHelper < DefColHelperBase
		def Key *labels
			if labels.empty?
				raise ArgumentError.new "missing label"
			else
				@toHelp.define_cols @type, true, false, false, *labels
			end
		end
		def Unique *labels
			if labels.empty?
				DefColHelperUnique.new @type, @toHelp
			else
				@toHelp.define_cols @type, false, true, false, *labels
			end
		end
		def NotNull *labels, **hsh
			if labels.empty? && hsh.empty?
				DefColHelperNotNull.new @type, @toHelp
			else
				@toHelp.define_cols @type, false, false, true, *labels, **hsh
			end
		end
	end
	class DefColHelperUnique < DefColHelperBase
		def NotNull *labels
			if labels.empty?
				raise ArgumentError.new "missing label"
			else
				@toHelp.define_cols @type, false, true, true, *labels
			end
		end
	end
	class DefColHelperNotNull < DefColHelperBase
		def Unique *labels
			if labels.empty?
				raise ArgumentError.new "missing label"
			else
				@toHelp.define_cols @type, false, true, true, *labels
			end
		end
	end
	public
	def define_cols t, isKey, isUnique, isNotNull, *labels, **hsh
		check_init do
			labels.each do |l|
				@__col_type__[l] = t
				check_col_obj l
				@__is_key__[l] = isKey if isKey
				@__is_unique__[l] = isUnique if isUnique
				@__is_not_null__[l] = isNotNull if isNotNull
			end
			hsh.each do |l, v|
				@__col_type__[l] = t
				check_col_obj l
				@__def_val__[l] = v
				@__is_key__[l] = isKey if isKey
				@__is_unique__[l] = isUnique if isUnique
				@__is_not_null__[l] = isNotNull if isNotNull
			end
		end
	end
	def primaryKey &bl
		sc = Class.new(SentenceContext)
		@labels = []
		begin
			obj = sc.new
			def obj.foo bl2
				instance_eval &bl2
			end
			obj.foo bl
		rescue NameError => e
			p e
			case e.to_s
			when /constant\s+.*::()([^\s]+)/
				p $2, @labels
				if @labels.include? $2.strip.intern
					print e
					exit 1
				else
					@labels.push $2.strip.intern
					ASchema::Goo.class_eval %{
						ABC = 100
					}
					sc.class_eval %{
						#{@labels[-1]} = 1
					}
					retry
				end
			when /undefined (local variable or |)method \`(.*?)\'/
				p $2
				@labels.push $2.strip.intern
				sc.class_eval %{
					def #{@labels[-1]}
					end
				}
				retry
			else
				raise $!
			end
		end
		p @labels
	end
	private
	def def_it type, *labels, **hsh
		p type, *labels, **hsh
		if labels.empty? && hsh.empty?
			DefColHelper.new type, self
		else
			define_cols type, false, false, false, *labels, **hsh
		end
	end
	[:String, :Integer, :Float].each do |t|
		class_eval %{
			def #{t} *labels, **hsh
				def_it :#{t}, *labels, **hsh
			end
		}
	end
	def Key *labels
		check_init do
			labels.each do |l|
				@__is_key__[l] = true
				check_col_obj l
			end
		end
	end
	def Unique *labels
		check_init do
			labels.each do |l|
				@__is_unique__[l] = true
				check_col_obj l
			end
		end
	end
	def Check &prc
		check_init do
			@__check_proc__.push prc
		end
	end
	def NotNull *labels
		check_init do
			labels.each do |l|
				@__is_not_null__.push l
				check_col_obj l
			end
		end
	end
	SQLExecMethod.each do |m|
		class_eval %{
			def #{m} (...)
				close_definition
				#{m}(...)
			end
		}
	end
	def [] (*args)
		close_definition
		self[*args]
	end
	def close_definition
		(SQLTableDefine.instance_methods(false) + SQLTableDefine.private_instance_methods(false)).each do |m|
			p.cyan m
			class_eval %{
				begin
					remove_method :#{m}
					alias_method :#{m}, :__Org_#{m}
				rescue NameError
				end
			}
		end
		extend SQLTableMethods
		__construct_table__
	end
end


module SQLString
	refine String do
		def sqlDquote
			self.gsub '"', "\"\""
			'"' + self + '"'
		end
		def sqlSquote
			self.gsub "'", "''"
			"'" + self + "'"
		end
	end
end
module SQLSymbol
	refine Symbol do
		def sqlDquote
			self.to_s.gsub '"', "\"'\"'\""
			'"' + self.to_s + '"'
		end
		def sqlSquote
			self.to_s.gsub "'", "'\"'\"'"
			"'" + self.to_s + "'"
		end
	end
end

using SQLString
using SQLSymbol

module SQLTable
	refine Class do
		(SQLTableDefine.instance_methods(false) + SQLTableDefine.private_instance_methods(false)).each do |m|
			if m != :[]
				eval %{
					private
					def #{m} (...)
						(class << self; self; end).class_eval do
							begin
								alias_method :__Org_#{m}__, :#{m}
							rescue NameError
							end
						end
						extend SQLTableDefine
						#{m}(...)
					end
				}
			else
				eval %{
					private
					def [] (*args)
						(class << self; self; end).class_eval do
							begin
								alias_method :__Org_#{m.to_s.underscore_escape}__, :#{m}
							rescue NameError
							end
						end
						extend SQLTableDefine
						self[*args]
					end
				}
			end
		end
	end
end


module SQLTableMethods
	class STreeElem
		def or
		end
		def and
		end

	end
	class StaticExpr < STreeElem

	end
	class Column < STreeElem
		attr_reader :parent, :label
		def initialize tableClass, l, defVal, isKey, isUnique, isNotNull, reference
			@parent = tableClass
			@label = l
			@isKey = isKey
			@isUnique = isUnique
			@isNotNull = isNotNull
			@reference = reference
			@default = defVal
		end
		def coerce a
			[StaticExpr.new(a), self]
		end
		@@toColumnClass = {}
		def self.[] type
			@@toColumnClass[type]
		end
		def self.registerColClass
			@@toColumnClass[self.name.split(/::/)[-1][0...-3].intern] = self
		end
	end
	class Where
	end
	class Select
		def sort_by *args, &prc
			sc = @sContext.class.new *args, &prc
			SortBy.new sc, self
		end
		def each *args, &prc
		end
		def [] *args
		end
		def initialize sc
			@sContext = sc
		end
	end
	class StringCol < Column
		registerColClass
		def self.compat? v
			v.is_a? String
		end
		def self.sqlType
			"text"
		end
	end
	class IntegerCol < Column
		registerColClass
		def self.compat? v
			v.is_a?(Integer) && -9223372036854775808 < v && v < 9223372036854775807
		end
		def self.sqlType
			"bigint"
		end
	end
	class FloatCol < Column
		registerColClass
		def self.compat? v
			v.is_a?(Float) || v.is_a?(Integer)
		end
		def self.sqlType
			"double precision"
		end
	end

	def __construct_table__
		%W{__def_val__ __is_key__ __is_unique__ __is_not_null__ __reference__}.each do |prp|
			eval %{
				p "#{prp}", @#{prp}
				if !(ekeys = @#{prp}.keys - @__col_type__.keys).empty?
					raise ArgumentError.new("extra label \#{ekeys.inspect} found in #{prp}")
				end
			}
		end
		@__def_val__.each do |l, v|
			if !Column[@__col_type__[l]].compat? v
				raise Error.new("Value, #{v.inspect} is not compatible to Column '#{l}'.")
			end
		end
		if !(tmp = @__is_key__.keys & @__is_unique__.keys).empty?
			STDERR.write("Warning: #{tmp.inspect} is primary key, always unique")
		end
		if !(tmp = @__is_key__.keys & @__is_not_null__.keys).empty?
			STDERR.write("Warning: #{tmp.inspect} is primary key, always not null")
		end
		if !(tmp = @__is_key__.keys & @__def_val__.keys).empty?
			die = true
			STDERR.write("#{tmp.inspect} is key, but default value specified")
		end
		if !(tmp = @__is_unique__.keys & @__def_val__.keys).empty?
			die = true
			STDERR.write("#{tmp.inspect} is unique, but default value specified")
		end
		if !(tmp = @__is_key__.keys & @__reference__.keys).empty?
			die = true
			STDERR.write("#{tmp.inspect} is key, but referencing other")
		end
		if !(tmp = @__is_unique__.keys & @__reference__.keys).empty?
			die = true
			STDERR.write("#{tmp.inspect} is referencing other, but unique attribute is specified")
		end
		if !(tmp = @__is_not_null__.keys & @__reference__.keys).empty?
			die = true
			STDERR.write("#{tmp.inspect} is referencing other, but 'not null' attribute is specified")
		end
		if !(tmp = @__def_val__.keys & @__reference__.keys).empty?
			die = true
			STDERR.write("#{tmp.inspect} is referencing other, but defalt value is specified")
		end
		if die
			raise ArgumentError.new("cannot construct table, #{self}")
		end
		@sentenceContextClass = Class.new(SentenceContext)
		@__col_obj__ = {}
		p @__col_type__
		@__col_type__.each do |l, t|
			p l, t
			p Column[t]
			colObj =  Column[t].new(self, l, @__def_val__[l], @__is_key__[l], @__is_unique__[l], @__is_not_null__[l], @__reference__[l])
			@__col_obj__[l] = colObj
			instance_variable_set('@' + l.to_s, colObj)
			@sentenceContextClass.define_method l do
				colObj
			end
		end
		check_definition
	end
	SQLExecMethod.each do |m|
		class_eval %{
			begin
				remove_method :#{m}
			rescue
			end
			def #{m} (...)
				check_definition
				#{m}(...)
			end
		}
	end

	def dbCreate
		cols = @__col_obj__.values.map { |co|
			p co
			[co.label.dquote, co.class.sqlType] * " "
		} * ", "
		p.purple "CREATE TABLE #{name.dquote} (#{cols})"
		#execSQL "CREATE TABLE #{name} (#{cols})"
	end

	def check_definition
		extend SQLTableExec
		if dbDefinition.then do
			if _1 != self
				raise Error.new("Table structure altered")
			end
		end;else
			dbCreate
		end
	end


	def initialize **data
		miskeys = self.class.__keys__ - data.keys
		if !miskeys.empty?
			raise Error.new("Columns, #{miskeys * ','} are not specified to a row for '#{self.class}'")
		end
		data.each do |k, v|
			if self.class.__columns__.keys.include? k
				if self.class.__columns__[k].compat? v
					instance_variable_set('@' + k.to_s, v)
				else
					raise Error.new("Value, #{v.inspect} is not compatible to Column '#{k}'.")
				end
			else
				raise Error.new("Column, '#{k}' does not exist in table, '#{self.class}'")
			end
		end
		(self.class.__default_vals__.keys - data.keys).each do |k|
			instance_variable_set('@' + k.to_s, self.class.__default_vals__[k])
		end
	end
	def inherited subclass # defile Capital Letter Function like "TableFoo{colA == 1 && colB == false}.each"
		@sentenceContext = subclass.class_eval %{
			class SContext < SentenceContext
				self
			end
		}
		binding.of_caller(2).define_method subclass.to_s do |&prc|
			close_def
			sc = @sentenceContext.new prc
		end
	end

	def anotherConnection **opts
		(c = clone).class_eval do
			@connectOptions = opts._![:empty?]
			SQLExecMethod.each do |m|
				class_eval %{
					remove_method :#{m}
					def #{m} (...)
						check_definition
						#{m}(...)
					end
				}
			end
			extend SQLTableMethods
		end
		c
	end
	@@connectionList = {}
	def execSQL sql
		(@@connectionList[@connectOptions] ||= PGSetup.connectIt(**@connectOptions)).exec sql
	end
end

module SQLTableExec
	def insert (**hash)
		p.green hash
		#close_def
	end
	def sort_by &prc
		close_def
		@sentenceContext.new prc
	end
	def each
		close_def
	end
	def [] *args
		close_def
	end
	def select &prc
		close_def
		sc = @sentenceContext.new prc
		sc.select self
	end

end