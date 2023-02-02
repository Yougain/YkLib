#!/usr/bin/env ruby

module TTYChar

DumpFile = File.dirname(__FILE__) + "/tty_char.dump"

Alt = {
	"\0" => '<NULL>',
	"\b" => '<BS>',
	"\r" => '<CR>',
	"\n" => '<LF>',
	"\a" => '<BELL>',
	"\t" => '<TAB>',
	"\x7f" => '<DEL>',
	"\x1b" => '<ESC>',
	"\u061C" => '<ALM>',
	"\u200E" => '<LRM>',
	"\u200F" => '<RLM>',
	"\u202A" => '<LRE>',
	"\u202B" => '<RLE>',
	"\u202C" => '<PDF>',
	"\u202D" => '<LRO>',
	"\u202E" => '<RLO>',
	"\u2066" => '<LRI>',
	"\u2067" => '<RLI>',
	"\u2068" => '<FSI>',
	"\u2069" => '<PDI>'
}

	begin
#		require 'Yk/debug2'
#		p 1
		Width = Marshal.load(File.open(DumpFile).read)
#		require 'Yk/tty_char_static'
#		p 2
	rescue
		require 'Yk/tty_char_create'
	end
end


if __FILE__ == $0
	require 'Yk/debug2'
	p TTYChar::Width["あ"]
	p TTYChar::Width["\x00"]
	p TTYChar::Width["\uffff"]
end