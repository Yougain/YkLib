

require 'Yk/path_aux'
require 'net/smtp'
require 'net/pop'
require 'thread'
require 'Yk/misc_tz'
require 'Yk/procinfo'



class RemoteMail < String
	def send (content, subject = nil)
		LocalMail.each do |m|
			m.sendTo(self, content, subject)
		end
	end
	def self.setMails (lmdir = "/etc/local_mail/remote".check_dir)
		if !defined? @@mails
			@@mails = []
			lmdir.each_entry do |f|
				if f =~ /\@/
					i = 0
					@@mails.push RemoteMail.new(f.basename)
				end
			end
			if !@@mails.significant?
				raise LocalMail::Error.new("cannot find mail configuration")
			end
		end
		@@mails
	end
	def self.send (content, subject = nil)
		if !defined? @@mails
			setMails
		end
		@@mails.each do |e|
			e.send content, subject
		end
		LocalMail.flush
	end
end


class LocalMail < String
	class Error < Exception
	end
	DEF_LIST = %w[
		SMTP_SERVER
		SMTP_ACCOUNT
		SMTP_PASSWD
		POP_SERVER
		POP_ACCOUNT
		POP_PASSWD
		POP_BEFORE_SMTP
	]
	@@localMails = []
	def initialize (fileName)
		super fileName.basename
		if CYGWIN || Process.euid == 0
			fileName.read_each_line do |ln|
				ln.strip_comment!
				if ln.significant?
					res = ln.getDefinition DEF_LIST do |k, v|
						instanceVariableSet(k, v)
					end
					if !res
						raise LocalMail::Error.new("illeagal line `#{ln}' at #{i}")
					end
				end
			end
			if !@popAccount
				@popAccount = self
			end
			if !@smtpAccount
				@smtpAccount = @popAccount
			end
			if !@smtpPasswd
				@smtpPasswd = @popPasswd
			end
		end
		@mutex = Mutex.new
		@fmutex = Mutex.new
		@rmutex = Mutex.new
		@mail = self
		@queue = []
		@@localMails.push self
	end
	def recieve mode = nil
		@rmutex.synchronize do
			begin
				pobj = Net::POP3.new(@popServer, 110)
				pobj.open_timeout = 1200
				pobj.start(@popAccount, @popPasswd) do |pop|
					if mode == ""
						next
					end
					hash = Hash.new
					pop.each_mail do |m|
						if mode == "flush"
							m.delete
							next
						end
						pop = m.pop.gsub /\r\n/, "\n"
						begin
							begin
								yield pop #MailipReciever::MailContent.new(m.pop)
							ensure
								m.delete
							end
						rescue Exception, SignalException => e
							raise Reexception.new
						end
					end
				end
			rescue Reexception => e
				e.reraise
			rescue Exception, SignalException => e
				emsg = ""
				if e.to_s != ""
					emsg = " (#{e.to_s.gsub(/\s+/, ' ').strip})"
				end
				errln "#{e.class.to_s}: failed to retrieve a mail from #{@mail}#{emsg}"
			end
		end
	end
	def sendTo (toAdr, content, subject = nil)
		if @popBeforeSmtp
			recieve @popBeforeSmtp
		end
		if subject
			t = content
			content = subject
			subject = t
		end
		c = -%{
			Date: #{arr = Time.now.localtime.to_s.split; arr[0] + ', ' + arr[2] + ' ' + arr[1] + ' ' + arr[5] + ' ' + arr[3] + ' ' + arr[4]}
			From: #{ProcInfo.current.cmdline.shellDQuote} <#{self}>
			To: #{toAdr}
			Subject: #{subject}
		}
		c += "\n" + content.ln
		@mutex.synchronize do
			@queue.push [c, self, toAdr]
		end
	end
	def flush
		@mutex.synchronize do
			if @queue.size == 0
				return
			end
		end
		@fmutex.synchronize do
			connectRetryCount = 0
			begin
				connectRetryCount += 1
				Net::SMTP.start(@smtpServer, 25, 'localhost.localdomain', @smtpAccount, @smtpPasswd, :login) do |smtp|
					while true
						gotItem = false
						params = nil
						@mutex.synchronize do
							if @queue.size > 0
								params = @queue.shift
								gotItem = true
							end
						end
						if !gotItem
							break
						end
						content, fromAdr, toAdr = params
						retryCount = 0
						begin
							retryCount += 1
							smtp.send_mail content, fromAdr, toAdr
						rescue Exception => e
							errln "cannot send from #{fromAdr} to #{toAdr} (#{e.class}:#{e.to_s.gsub(/\s+/, ' ')}.strip); Retring....".ln
							sleep 10
							if retryCount > 3
								errln "All retrials failed. Giving up sending from #{fromAdr} to #{toAdr}.".ln
							else
								retry
							end
						end
					end
				end
			rescue => e
				errln "cannot complete sending mails from #{self} (#{e.class}:#{e.to_s.gsub(/\s+/, ' ')}.strip); Retrying....".ln
				sleep 10
				if connectRetryCount > 3
					errln "All retrials failed. Giving up sending mails from #{self}.".ln
				else
					retry
				end
			end
		end
	end
	def self.chkMails
		if !defined? @@mails
			setMails
		end
	end
	def self.recieve
		chkMails
		tList = []
		@@localMails.each do |m|
			t = Thread.new do
				m.recieve do |c|
					yield c
				end
			end
			tList.push t
		end
		tList.each do |t|
			t.join
		end
	end
	def self.setMails (lmdir = "/etc/local_mail/local".check_dir)
		if !defined? @@mails
			@@mails = []
			lmdir.each_entry do |f|
				if f =~ /\@/
					i = 0
					@@mails.push LocalMail.new(f)
				end
			end
			if !@@mails.significant?
				raise LocalMail::Error.new("cannot find mail configuration")
			end
		end
		@@mails
	end
	def self.each
		chkMails
		@@mails.each do |e|
			yield e
		end
	end
	def self.flush
		chkMails
		@@localMails.each do |m|
			m.flush
		end
	end
	def self.keep
		chkMails
		@@localMails.each do |m|
			m.receive ""
		end
	end
end


class RemoteMail < String
	def send (content, subject)
		sendToAdmin(content, subject)
		#LocalMail.each do |m|
		#	m.sendTo(self, content, subject)
		#end
	end
	def sendTo (mail, content, subject)
		LocalMail.each do |m|
			m.sendTo(mail, content, subject)
		end
	end
	def sendToAdmin (content, subject)
		if (mf = "/etc/local_mail/admin").readable_file?
			adminMail = mf.read.strip
			sendTo adminMail, content, subject
		else
			STDERR.write "#{$0}: cannot send mail: please set /etc/local_mail/admin\n"
		end
	end
end



