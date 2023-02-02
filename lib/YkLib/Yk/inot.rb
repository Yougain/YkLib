

if RUBY_PLATFORM =~ /linux/

	require 'inotify'
	require 'Yk/path_aux'
	require 'thread'

	class InotD
		@@allList = []
		def initialize (d, wparam, prc, f)
			@int = Inotify.new
			@d = d
			@int.add_watch @d, wparam
			@prcList = Hash.new{|h, k| h[k] = []}
			@prcList[f].push prc
			@m = Mutex.new
			@@allList.push self
			@t = Thread.new do
				begin
					@int.each_event do |ev|
						@prcList.each do |e, aprc|
							if e == ev.name || e == nil
								aprc.each do |prc|
									begin
										prc.call ev.name, ev.mask
									rescue SystemExit
										raise
									rescue Exception => e
										STDERR.write "#{e.class}:#{e}\n"
										e.backtrace.each do |e|
											STDERR.write "\t#{e}\n"
										end
									end
								end
							end
						end
					end
				ensure
					@closed && @int.close
					@closed = true
				end
			end
		end
		def readd_watch (wparam, prc, f)
			@m.synchronize do
				@int.add_watch @d, wparam
				@prcList[f].push prc
			end
		end
		@@m = Mutex.new	
		@@iList = Hash.new
		def self.emerge (d, wparam, prc, f = nil)
			obj = nil
			@@m.synchronize do
				if !(obj = @@iList[d])
					obj = @@iList[d] = InotD.new(d, wparam, prc, f)
					return obj
				end
			end
			obj.readd_watch wparam, prc, f
			obj
		end
		def close_watch (f, prc)
			@m.synchronize do
				(a = @prcList[f]).delete prc
				if a.size == 0
					@prcList.delete f
				end
				if @prcList.size != 0
					return
				end
			end
			Thread.kill @t
			@@m.synchronize do
				@@iList.delete @d
				@int.close
			end
		end
		def join
			@t.join
		end
		def self.join
			@@allList.each do |obj|
				obj.join
			end
		end
	end
	class Inot
		def self.join
			InotD.join
		end
		ACCESS		= Inotify::ACCESS
		MODIFY		= Inotify::MODIFY	
		ATTRIB		= Inotify::ATTRIB	
		CLOSE_WRITE		= Inotify::CLOSE_WRITE		
		CLOSE_NOWRITE	= Inotify::CLOSE_NOWRITE
		OPEN			= Inotify::OPEN			
		MOVED_FROM		= Inotify::MOVED_FROM		
		MOVED_TO		= Inotify::MOVED_TO		
		CREATE		= Inotify::CREATE		
		DELETE		= Inotify::DELETE		
		DELETE_SELF		= Inotify::DELETE_SELF		
		MOVE_SELF		= Inotify::MOVE_SELF		
		UNMOUNT		= Inotify::UNMOUNT		
		Q_OVERFLOW		= Inotify::Q_OVERFLOW		
		IGNORED		= Inotify::IGNORED		
		CLOSE			= Inotify::CLOSE			
		MOVE			= Inotify::MOVE			
		MASK_ADD		= Inotify::MASK_ADD		
		ISDIR			= Inotify::ISDIR			
		ONESHOT		= Inotify::ONESHOT		
		ALL_EVENTS		= Inotify::ALL_EVENTS		
		def initialize (path, wparam, prc)
			prc2 = Proc.new do |n, flg|
				args = [n, flg][0..prc.arity - 1]
				if !@base
					prc.call *args
				else
					prc.call *args
				end
			end
			@prc = prc2
			if path.exist?
				rpath = path.realpath
				if path.directory?
					@base = nil
					@inotD = InotD.emerge rpath, wparam, prc2
				else
					@base = rpath.basename
					@inotD = InotD.emerge rpath.dirname, wparam, prc2, @base
				end
			elsif path.dirname.directory?
				rpath = path.dirname.realpath
				@base = path.basename
				@inotD = InotD.emerge rpath, wparam, prc2, @base
			else
				ArgumentError.new "#{path.dirname} does not seem a directory."
			end
		end
		def close
			@inotD.close_watch(@base, @prc)
		end
		def join
			@inotD.join
		end
		class Arr < Array
			def close
				each do |e|
					e.close
				end
			end
			def join
				each do |e|
					e.join
				end
			end
		end
	end


	class String
		def at_modified (mode = Inot::MODIFY|Inot::DELETE|Inot::CREATE, &bl)
			Inot.new self, mode, bl
		end
	end


	class Array
		def at_modified (mode = Inot::MODIFY|Inot::DELETE|Inot::CREATE, &bl)
			m = Mutex.new
			b2 = Proc.new do |f, msk|
				m.synchronize do
					if bl.arity == 1
						bl.call f
					else
						bl.call f, msk
					end
				end
			end
			ia = Inot::Arr.new
			each do |e|
				ia.push e.at_modified(mode, &b2)
			end
			ia
		end
	end


elsif RUBY_PLATFORM =~ /cygwin/

	require 'Win32API'
	require 'Yk/path_aux'

	module Win32

		INVALID_HANDLE_VALUE = -1
		INFINITE = 0xFFFFFFFF
		WAIT_OBJECT_0 = 0x00000000
		WAIT_TIMEOUT = 0x00000102
		WAIT_FAILED = 0xFFFFFFFF
		FILE_NOTIFY_CHANGE_FILE_NAME   = 0x00000001
		FILE_NOTIFY_CHANGE_DIR_NAME    = 0x00000002
		FILE_NOTIFY_CHANGE_ATTRIBUTES  = 0x00000004
		FILE_NOTIFY_CHANGE_SIZE        = 0x00000008
		FILE_NOTIFY_CHANGE_LAST_WRITE  = 0x00000010
		FILE_NOTIFY_CHANGE_LAST_ACCESS = 0x00000020
		FILE_NOTIFY_CHANGE_CREATION    = 0x00000040
		FILE_NOTIFY_CHANGE_SECURITY    = 0x00000100

		FindFirstChangeNotification = Win32API.new("kernel32", "FindFirstChangeNotification", ['P', 'I', 'L'], 'L')
		FindNextChangeNotification = Win32API.new("kernel32", "FindNextChangeNotification", ['L'], 'I')
		WaitForMultipleObjects = Win32API.new("kernel32", "WaitForMultipleObjects", ['L', 'P', 'I', 'L'], 'L')
		WaitForSingleObject = Win32API.new("kernel32", "WaitForSingleObject", ['P', 'L'], 'L')
		CloseHandle = Win32API.new("kernel32", "CloseHandle", ['P'], 'L')

		module Event

			def self.FindChangeNotification(dir_name='.', is_watch_subtree=false)
				dir_name = %W{cygpath -w #{dir_name}}.read_p.chomp
				# 指定のディレクトリ中の変更を監視する。
				# 変更があったら、ブロックの有無によりyieldまたはreturn
				h = 
					FindFirstChangeNotification.Call(
						dir_name, (is_watch_subtree ? 1 : 0), 
						FILE_NOTIFY_CHANGE_LAST_WRITE |
						FILE_NOTIFY_CHANGE_CREATION |
						FILE_NOTIFY_CHANGE_FILE_NAME
					)
				return nil if h == INVALID_HANDLE_VALUE
			
				begin
					loop {
						wait_start = Time.now
						return nil if WAIT_FAILED == WaitForSingleObject.Call(h, INFINITE)
						if block_given?
							yield if Time.now - wait_start > 0.1
						else
							return true
						end
						return nil if 0 == FindNextChangeNotification.Call(h)
					}
				ensure
					CloseHandle.call(h)
				end
			end

		end

	end


	class String
		def at_modified
			Thread.new do
				Win32::Event::FindChangeNotification self do
					yield
				end
			end
		end
	end


end

