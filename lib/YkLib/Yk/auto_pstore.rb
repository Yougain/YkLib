
require 'pstore'
require 'Yk/path_aux'


class AutoPstore
	@@readOnly = false
	@@fileName = File.basename($0)
	def initialize
        dbFile = "/var/tmp/#{@@fileName}.auto_pstore.db"
        dbFileDeb = "/var/tmp/#{@@fileName}.auto_pstore.debug.db"
        if $DEBUG
			if !dbFileDeb.exist? && dbFile.exist?
	            dbFile.copy(dbFileDeb)
			end
            dbFile = dbFileDeb
		end
		if defined?(@@readTemp) && @@readTemp
			"/var/tmp/#{@@fileName}.auto_pstore.lock".lock_sh do
				db = PStore.new(dbFile)
				db.transaction true do
					@objList = db["root"]
				end
			end
		else
			retried = false
			begin
        		"/var/tmp/#{@@fileName}.auto_pstore.lock".setpid
        	rescue File::CannotGetLock
        		raise Exception.new("AutoPstore: second instance is not allowed")
        	end
			begin
				db = PStore.new(dbFile)
			rescue
				if !retried
					dbFile.rm_f
					retried = true
					retry
				else
					raise Exception.new("cannot open database\n")
					exit 1
				end
			end
			@sleeping = false
			@thread = Thread.new do
				db.transaction @@readOnly do
					@objList = db["root"] ||= Hash.new
					Thread.pass
					@sleeping = true
					sleep
				end
			end
			ctmp = 0
			while !@objList
				Thread.pass
				sleep 0.1
				ctmp += 1
				if ctmp > 10
					raise Exception.new("cannot open/create database\n")
				end
			end
			@objList.each_value do |e|
				if e.respond_to? :check_recover
					e.check_recover
				end
			end
			@finalizer = Hash.new{ |h, k| h[k] = Hash.new }
			at_exit do
				close
			end
		end
	end
	def setFinalizer (name, obj = nil, &bl)
		@finalizer[name][obj] = bl
	end
	def method_missing (name, *args)
		if name.to_s[-1] == ?=
			tmp = name.to_s.chop
#			if @objList[tmp] != nil
#				raise Exception.new("cannot register twice (#{tmp})\n")
#			else
				@objList[tmp] = args[0]
#			end
		else
			@objList[name.to_s]
		end
	end
	def each
		@objList.each do |k, v|
			yield k, v
		end
	end
	def AutoPstore.method_missing (name, *args)
		if !defined?(@@autoPstore) || @@readTemp
			@@autoPstore = AutoPstore.new
		end
		@@autoPstore.method_missing(name, *args)
	end
	def AutoPstore.each
        if !defined? @@autoPstore
            @@autoPstore = AutoPstore.new
        end
		@@autoPstore.each do |k, v|
			yield k, v
		end		
	end
	def AutoPstore.setFinalizer (name, target)
		if !defined? @@autoPstore
			@@autoPstore = AutoPstore.new
		end
		@@autoPstore.setFinalizer(name, target)
	end
	def AutoPstore.close
		if defined? @@autoPstore
			@@autoPstore.close
			@@autoPstore = nil
		end
	end
	def AutoPstore.transaction
		if !defined? @@autoPstore
			@@autoPstore = AutoPstore.new
			begin
				yield
			ensure
				close
			end
		else
			raise Exception.new("AutoPstore already opened\n")
		end
	end
	def AutoPstore.setReadOnly
		@@readOnly = true
		self
	end
	def AutoPstore.setFileName f
		@@fileName = f
		self
	end
	def AutoPstore.readTemp
		@@readTemp = true
		self
	end
	def close
		if !@closed
			@closed = true
			if @finalizer
				@finalizer.each do |name, o|
					o.each_value do |prc|
						prc.call @objList[name]
					end
				end
				while !@sleeping
					begin
						@thread.run
					rescue ThreadError
						Thread.pass
						sleep 1
						if !@sleeping
							raise Exception.new("abnormal variable @sleep = #{@sleep} detected at #{__LINE__} in #{__FILE__}.")
						end
					end
					Thread.pass
					sleep 1
				end
				begin
					@thread.run
				rescue ThreadError
				end
				begin
					@thread.join
				rescue ThreadError
				end
			end
		end
	end
end



