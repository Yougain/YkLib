require 'etc'

	class UserInfo
		@@userList = Hash.new
		def self.name arg = nil
			emerge(arg).name
		end
		def self.home arg = nil
			emerge(arg).home
		end
		def self.id arg = nil
			emerge(arg).id
		end
		def self.emerge arg
			arg ||= ENV['USER'] || Process.euid
			@@userList[arg] || new(arg)
		end
		def initialize arg
			if arg.is_a? Integer
				@data = Etc.getpwuid arg
			elsif arg.is_a? String
				@data = Etc.getpwnam arg
			else
				raise ArgumentError.new("cannot use #{arg} for argument.")
			end
			@@userList[@data.uid] = self
			@@userList[@data.name] = self
		end
		def id
			@data.uid
		end
		def method_missing (label, *args)
			@data.method(label).call(*args)
		end
		def to_s
			@data.name
		end
		def to_i
			@data.uid
		end
		def home
			@data.dir
		end
		def group
			GroupInfo.emerge(@data.gid)
		end
	end
	class GroupInfo
		@@groupList = Hash.new
        def self.name arg = nil
            GroupInfo.emerge(arg).name 
        end 
        def self.id arg = nil
            GroupInfo.emerge(arg).id 
        end
		def self.emerge arg = nil
			if arg == nil
				if ENV['USER']
					arg = UserInfo.emerge(ENV['USER']).group.gid
				else
					arg = Process.egid
				end
			end
			@@groupList[arg] || new(arg)
		end
		def initialize arg
            if arg.is_a? Integer
                @data = Etc.getgrgid arg
            elsif arg.is_a? String
                @data = Etc.getgrnam arg
            else 
                raise ArgumentError.new("cannot use #{arg} for argument.")
            end 
            @@groupList[@data.gid] = self
            @@groupList[@data.name] = self
		end
		def id
			@data.gid
		end
        def method_missing (label, *args)
            @data.method(label).call(*args) 
        end 
        def to_s 
            @data.name
        end 
        def to_i 
            @data.gid
        end 
	end


