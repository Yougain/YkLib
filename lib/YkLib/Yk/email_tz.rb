#!/usr/bin/env ruby

require "net/smtp.rb"
require "base64"
require "kconv"
#require "iconv"
require 'Yk/path_aux'


################################################################################
#
#	String
#

	#---------------------------------------------------------------------------
	#
	#	mime encode
	#
def __encode_for_mime slf, mode = nil
	s = nil
	if !mode
		slf.each_char do |c|
			if !" \r\n\tabcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#\$%&'()=~^|`@{}*+:;<>,?/[]-\\._".include? c
				mode = :non_ascii
				break
			end
		end
		if mode != :non_ascii
			mode = "ascii"
		else
			begin
				s = slf.encode(Encoding::ISO2022_JP)
				mode = "jp"
			rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
				begin
					s = slf.encode("GB2312")
					mode = "zh"
				rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
					begin
						s = slf.encode("UTF-8")
						mode = "utf"
					rescue Encoding::InvalidByteSequenceError
					end
				end
			end
		end
		case mode
		when /^ascii$/i
			return slf, mode
		when /^jp$/i
			s ||= slf.encode(Encoding::ISO2022_JP)
			return s, mode
		when /^zh$/i
			s ||= slf.encode("GB2312")
			return s, mode
		when /^utf$/i
			s ||= slf.encode("UTF-8")
			return s, mode
		else
			return slf, mode
		end
	end
end

class String
	#---------------------------------------------------------------------------
	#
	#	mime decode
	#
	def mime_decode
		return self unless self =~ /^=\?(ISO-2022-JP|UTF-8|GB2312)\?B\?(.+)\?=$/i
		return Base64.decode64($1)
	end
	def google_link
		expr = self
		e2, mode = __encode_for_mime expr.strip
		case expr
		when /^\+81/
			url = "<a href='https://www.google.com/search?q=0#{$'}'>#{expr}</a>"
		when /^\+86/
			cnum = $'
			if cnum !~ /^1[1-9]\d\d\d\d\d\d\d\d\d$/
				cnum = "0" + cnum
			end
			url = "<a href='https://www.baidu.com/s?wd=#{cnum}'>#{expr}</a>"
		else
			case mode
			when "zh"
				url = "<a href='https://www.baidu.com/s?wd=#{cnum}'>#{expr}</a>"
			else
				url = "<a href='https://www.google.com/search?q=0#{$'}'>#{expr}</a>"
			end
		end
		url
	end
end

class MimeBody < String
	attr :body
	def initialize arg, mode = nil
		type = "plain"
		case arg
		when /\<\s*\/\s*html\s*\>/
			type = "html"
		when /\<\s*\/\s*a\s*\>/
			arg = "<html><pre>#{arg}</pre></html>"
			type = "html"
		end
		@body, @mode = __encode_for_mime(arg, mode)
		case @mode
		when /^ascii$/i
			@header = "Content-Type:text/#{type}\nContent-Transfer-Encoding: 7bit"
		when /^jp$/i
			@header = "Content-Type:text/#{type}; charset=\"ISO-2022-JP\"\nContent-Transfer-Encoding: 7bit"
		when /^zh$/i
			@header = "Content-Type:text/#{type}; charset=\"GB2312\"\nContent-Transfer-Encoding: 7bit"
		when /^utf$/i
			@header = "Content-Type:text/#{type}; charset=\"UTF-8\"\nContent-Transfer-Encoding: base64"
			@body = Base64.encode64(@body)
		end
		super @header.force_encoding("ascii-8bit") + "\n\n" + @body.force_encoding("ascii-8bit")
	end
end

class MimeHeader < String
	def initialize arg, mode = nil
		if arg =~ /:/
			@title = $` + $&
			@content, @mode = __encode_for_mime($', mode)
			case @mode
			when /^ascii$/i
			when /^jp$/i
				@content = "=?ISO-2022-JP?B?" + Base64.encode64(@content.chomp).gsub!(/\n/, "") + "?=\n"
			when /^zh$/i
				@content = "=?GB2312?B?" + Base64.encode64(@content.chomp).gsub!(/\n/, "") + "?=\n"
			when /^utf$/i
				@content = "=?UTF-8?B?" + Base64.encode64(@content.chomp).gsub!(/\n/, "") + "?=\n"
			end
			super @title.force_encoding("ascii-8bit") + @content.force_encoding("ascii-8bit")
		else
			super arg
		end
	end
end

class String
	def mime_encode mode = nil
		MimeHeader.new self, mode
	end
end



module TZEMail
	################################################################################
	#
	#	Email
	#
	class Email

		attr_reader		:header
		attr_reader		:body
		attr_accessor	:smtpServer

		#---------------------------------------------------------------------------
		#
		#	Initialize メールオブジェクトを生成する
		#
		def initialize(mail = nil)	# mail = Array or IO(ex.STDIN) or nil
			key     = nil
			@header = {}
			@body   = []

			return if mail == nil

			inBody = false
			mail.each {|line|
				line.chomp!
				unless inBody
					if line =~ /^$/					# 空行
						inBody = true
					elsif line =~ /^(\S+?):\s*(.*)/	# ヘッダ行
						key = $1.capitalize
						@header[key] = $2
					elsif key						# ヘッダ行が2行に渡る場合
						@header[key] += "\n" + line.sub(/^\s*/, "\t")
					end
				else
					@body.push(line)
				end
			}
		end

		#---------------------------------------------------------------------------
		#
		#	[] ヘッダを参照
		#
		def [](key)
			@header[key.capitalize]
		end

		#---------------------------------------------------------------------------
		#
		#	[]= ヘッダを設定
		#
		def []=(key, value)
			@header[key.capitalize] = value
		end

		#---------------------------------------------------------------------------
		#
		#	<< ボディにテキストを追加
		#
		def <<(message)
			@body.push message
		end

		#---------------------------------------------------------------------------
		#
		#	encode メールをテキストストリームにエンコード
		#
		def encode
			mail = ""
			@header.each {|key, value|
				mail += "#{key}: #{value}\n"
			}
			mail += "\n"							# ヘッダ/ボディのセパレータ
			@body.each {|message|
				mail += "#{message}\n"
			}
			return mail
		end

		#---------------------------------------------------------------------------
		#
		#	send メールを送る
		#
		def send server = "localhost", user = nil, passwd = nil, auth = nil
			from  = @header['From']
			to = []
			to.push @header['To']
			Net::SMTP.start(server, 25, 'localhost.localdomain', user, passwd, auth) {|smtp|
				smtp.send_mail(self.encode, from, *to)
			}
		end
	end

	################################################################################
	#
	#	EncodedEmail
	#
	class EncodedEmail < Email

		#---------------------------------------------------------------------------
		#
		#	Decode メールブロックをデコード
		#
		def decode
			if self['Content-transfer-encoding'] =~ /base64/i
				return Base64.decode64(@body.join)
			else
				return @body.join("\n")
			end
		end

		#---------------------------------------------------------------------------
		#
		#	<< ボディにコンテントを追加
		#
		def <<(content)
			if self['Content-transfer-encoding'] =~ /base64/i
				@body = Base64.encode64(content).split("\n")
			else
				@body = content.split("\n")
			end
		end
	end

	################################################################################
	#
	#	AttachedEmail
	#
	class AttachedEmail < EncodedEmail

		attr_reader	:block

		#---------------------------------------------------------------------------
		#
		#	Initialize 添付メールオブジェクトを生成する
		#
		def initialize(mail = nil)

			super(mail)

			if mail == nil
				@separator = "separator" + (rand 65536).to_s
				self['MIME-Version'] = "1.0"
				self['Content-Type'] = "Multipart/Mixed; boundary=\"#{@separator}\""
				@block = []
				return
			end

			return unless self['Content-Type'] =~ /^Multipart\/Mixed;\s*boundary=(["']?)(.*)\1/i
			@separator = $2
			@block = []

			buf = []
			@body.each {|line|
				if line =~ /^--#{@separator}/
					@block.push(EncodedEmail.new(buf))
					buf = []
					next
				end
				buf.push(line)
			}

			@block.shift
			@body = []
		end

		#---------------------------------------------------------------------------
		#
		#	<< メールブロックを追加
		#
		def <<(block)
			@block.push(block)
		end

		#---------------------------------------------------------------------------
		#
		#	encode メールをテキストストリームにエンコード
		#
		def encode
			@block.each {|block|
				@body.push("--" + @separator)
				@body += block.encode.split("\n")
			}
			@body.push("--" + @separator + "--")
			super
		end
	end

end

class EMailSender
	attr_accessor :to, :from, :subject, :text, :server, :passwd, :user, :auth
	def initialize mode
		case mode
		when /^jp$/i
			@mode = "jp"
		when /^zh$/i
			@mode = "zh"
		end
		@attachedFiles = Hash.new
	end
	def attach file
		!file.readable_file? and raise(Exception.new("cannot read file #{f}"))
		@attachedFiles[file] = true
	end
	def detach file
		@attachedFiles.delete file
	end
	def getFileBlock f
		if f.readable_file?
			fBlock = TZEMail::EncodedEmail.new
			name = f.basename.mime_encode @mode
			ctype = f =~ /\.(jpg|jpeg|gif|png)$/ ? "Image/#{$1}" : "Application/Octet-Stream"
			fBlock['Content-Type'] =  "#{ctype}; name=\"#{name}\""
			fBlock['Content-transfer-encoding'] = "base64"
			fBlock << f.read
			fBlock
		else
			raise Exception.new("cannot read file #{f}")
		end
	end
	def charset
		case @mode
		when "jp"
			"charset=iso-2022-jp"
		when "zh"
			"charset=gb2312"
		else
			""
		end
	end
	def convert t
		case @mode
		when "jp"
			t.tojis
		else
			t
		end
	end
	def getTextBlock
		tBlock = TZEMail::Email.new
		tBlock['Content-Type'] = "Text/Plain; #{charset}"
		tBlock << convert(text)
		tBlock
	end
	def send *args
			email = TZEMail::AttachedEmail.new
			to and email['To'] = @to
			from and email['From'] = @from
			subject and (email['Subject'] = @subject.mime_encode @mode)
			if text
				email << getTextBlock
			end
			@attachedFiles.keys.each do |file|
				email << getFileBlock(file)
			end
			email.send(server, user, passwd, auth)
	end
	def EMailSender.send smtp, from, to, text, subject = nil, files = nil, xPriority = nil
		sendmail smtp, files, <<END
From: #{from}
#{subject && "Subject: #{subject}\n"}To: #{to}
Date: #{Time.now.strftime("%a, %e %b %Y %T %z").gsub(/\s+/, " ")}#{xPriority && "\nX-Priority: #{xPriority}"}

#{text}
END
	end
	TList = []
	def EMailSender.sendmail smtp, files, mail
		headers = []
		if mail =~ /\n\n/
			h, b = $` + "\n", $'
		else
			h, b = mail, ""
		end
		h.each_line do |ln|
			if ln !~ /^\s/ || headers.size == 0 
				headers.push ln
			else
				headers[-1] += ln
			end
		end
		mail = ""
		from = nil
		to = nil
		headers.each do |h|
			if h =~ /^From:/ && h =~ /[^<\s\"]+\@[^>\s\"]+/
				from = $&
			end
			if h =~ /^To:/ && h =~ /[^<\s\"]+\@[^>\s\"]+/
				to = $&
			end
			mail += MimeHeader.new h
		end
		if files && files.size > 0
			bdstr = "-------#{rand(1000000000)}#{rand(1000000000)}"
			bdstrb = "--" + bdstr
			mail += "Content-Type: multipart/mixed; boundary=\"#{bdstr}\"\n\n#{bdstrb}\n"
		end
		mail += MimeBody.new b
		if bdstr
			mail = mail.chomp.ln + bdstrb
			files.each do |f|
				case f
				when /\.(png|gif|bmp)$/i
					type = "image/#{$1.downcase}"
				when /\.(jpg|jpeg)$/i
					type = "image/jpeg"
				when /\.(tiff|tif)$/i
					type = "image/tiff"
				when /\.(text|txt)$/i
					type = "text/plain"
				when /\.csv$/i
					type = "text/csv"
				when /\.(html|htm)$/i
					type = "text/html"
				when /\.pdf$/i
					type = "application/pdf"
				when /\.(xls|xlsx)$/i
					type = "application/vnd.ms-exel"
				when /\.(doc|docx)$/i
					type = "application/msword"
				when /\.(doc|docx)$/i
					type = "application/msword"
				when /\.(ppt|pptx|pptm)$/i
					type = "application/vnd.ms-powerpoint"
				when /\.exe$/i
					type = "application/octet-stream"
				when /\.tar(|.*)$/i
					type = "application/x-tar"
				when /\.zip$/i
					type = "application/zip"
				when /\.lzh$/i
					type = "application/x-lzh"
				when /\.mp3$/i
					type = "audio/mpeg"
				when /\.mp4$/i
					type = "audio/mp4"
				when /\.mpeg$/i
					type = "video/mpeg"
				else
					type = "application/octet-stream"
				end
				mail += "\n"
				mail += MimeHeader.new "Content-Type: #{type}; name = \"#{f.basename}\"\n"
				mail += "Content-Transfer-Encoding: base64\n\n"
				mail += Base64.encode64(f.read).chomp.ln
				mail += bdstrb
			end
			mail += "--"
		end
		h, p = smtp.split(/:/)
		p ||= 25
		p = p.to_i
		pid = fork do
			fork do
				Net::SMTP.start(h, p) {|smtp|
					smtp.send_message(mail, from, to)
				}
				exit 0
			end
			exit 0
		end
	end
end


if __FILE__.basename == $0.basename
	sender = EMailSender.new "jp"
#	sender.text = "test"
	sender.text = "XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X"
	sender.subject = "テスト"
#	sender.attach "/root/eicar_com.zip"
	sender.to = "yougain@nifty.com"
	sender.from = "yuan@you.dix.asia"
	sender.send
end


