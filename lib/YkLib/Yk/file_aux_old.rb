# old style funcs
def File.l_open (f, mode = "r")
	fw = nil
	begin
		case mode
		when "w"
			fw = File.open f, File::WRONLY|File::CREAT|File::NONBLOCK
			fw.flock File::LOCK_EX
			fw.truncate 0
		when "a"
			fw = File.open f, File::WRONLY|File::CREAT|File::APPEND|File::NONBLOCK
			fw.flock File::LOCK_EX
		when "r"
			fw = File.open f, File::RDONLY|File::NONBLOCK
			fw.flock File::LOCK_SH
		when "w+"
			fw = File.open f, File::RDWR|File::CREAT|File::NONBLOCK
			fw.flock File::LOCK_EX
			fw.truncate 0
		when "a+"
			fw = File.open f, File::RDWR|File::CREAT|File::APPEND|File::NONBLOCK
			fw.flock File::LOCK_EX
		when "r+"
			fw = File.open f, File::RDWR|File::NONBLOCK
			fw.flock File::LOCK_EX
		end
		if block_given?
			yield fw
		end
	ensure
		if block_given?
			if fw
				fw.close
			end
		end
	end
	fw
end
def IO.pread (f)
	IO.popen(f).read
end
def IO.write (f, *c)
	File.open(f, "w") do |fw|
		c.each do |e|
			fw.write e
		end
	end
end
def IO.pwrite (f, *c)
	IO.popen f, "w" do |fw|
		c.each do |e|
			fw.write e
		end
	end
end
def IO.pwriteln (f, *c)
	IO.popen f, "w" do |fw|
		fw.writeln *c
	end
end
def IO.writeln (f, *args)
	File.open(f, "w") do |fw|
		fw.writeln *args
	end
end
def IO.l_write (f, *c)
	File.l_open(f, "w") do |fw|
		c.each do |e|
			fw.write e
		end
	end
end
def IO.l_read (f)
	c = nil
	File.l_open(f, "r") do |fr|
		c= fr.read
	end
	return c
end
def File.rewrite_each_line (fName, lock = false)
	File.open fName, File::RDWR|File::CREAT|File::NONBLOCK do |fw|
		lock && fw.flock(File::LOCK_EX)
		begin
			newLines = []
			modPos = nil
			ln = nil
			lnNew = nil
			pushNewLine = Proc.new do
				lnNew != "" && lnNew[-1] != ?\n && lnNew += "\n"
				newLines.push lnNew
			end
			fw.each_line do |ln|
				lnNew = yield ln
				if newLines.size == 0
					if lnNew != ln
						modPos = fw.pos - ln.size
						pushNewLine.call
					end
				else
					pushNewLine.call
				end
			end
			if (lnNew = yield("")) != ""
				if modPos == nil
					modPos = fw.pos
				end
				if ln != nil && ln[-1] != ?\n
					lnNew = "\n" + lnNew
				end
				pushNewLine.call
			end
			if newLines.size > 0
				fw.seek modPos
				newLines.each do |e|
					fw.write e
				end
				fw.truncate fw.pos
			end
		ensure
			lock && fw.flock(File::LOCK_UN)
		end
	end
end 
class File
	def File.nb_open (fName, flg = "r", &bl)
		open fName, IO::FMode.new(flg).to_i | File::NONBLOCK, &bl
	end
end
class IO
	def IO.nb_popen (cmd, flg = "r", &bl)
		IO.popen cmd, IO::FMode.new(flg).to_i | File::NONBLOCK, &bl
	end
end
class Array
	def nb_open (flg = "r", &bl)
		IO.nb_open condSQuote, flg
	end
	def nb_popen (flg = "r", &bl)
		IO.popen condSQuote, IO::FMode.new(flg).to_i | File::NONBLOCK, &bl
	end
end
def nb_open (flg, &bl)
	File.nb_open(flg, &bl)
end
class Tempfile
	class TempFifo < String
		def initialize
			super "/var/tmp/#{File.basename($0)}.#{rand(10000000000).to_s}.#{$$}.fifo"
			system "mkfifo /var/tmp/#{File.basename($0)}.#{rand(10000000000).to_s}.#{$$}.fifo"
			at_exit do
				rm_f
			end
		end
	end
	def self.mkfifo
		TempFifo.new
	end
end


