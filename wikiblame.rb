# coding: utf-8
# WikiBlame v 0.3 by Matma Rex
# matma.rex@gmail.com
# released under CC-BY-SA 3.0

require 'sunflower'
require 'camping'
require 'diff-lcs'

require 'benchmark'

Camping.goes :WikiBlameCamping

module WikiBlameCamping
	module Controllers
		class Index
			def get
				@title = "Wiki blame"
				render :index
			end
		end
		
		class SourceX
			def get file
				@headers['content-type']='text/plain'
				
				case file
				when 'README'
					@source1 ||= File.read './README'
				when 'wikiblame.rb'
					@source2 ||= File.read './wikiblame.rb'
				else
					'Nope.'
				end
			end
		end
		
		class Diff
			def get
				lang = (@request['lang'] and @request['lang']!='') ? @request['lang'] : 'pl'
				article = (@request['article'] and @request['article']!='') ? @request['article'] : ''
				reverts = (@request['reverts'] and @request['reverts']!='') ? true : false
				collapse = (@request['collapse'] and @request['collapse']!='') ? true : false
				revertshard = (@request['revertshard'] and @request['revertshard']!='') ? true : false
				pilcrow = (@request['pilcrow'] and @request['pilcrow']!='') ? true : false
				parsed = (@request['parsed'] and @request['parsed']!='') ? true : false
				colorusers = (@request['colorusers'] and @request['colorusers']!='') ? true : false
				granularity = (@request['granularity'] and @request['granularity']!='') ? @request['granularity'] : 'chars'
				
				blame = WikiBlame.new lang, article, reverts, collapse, revertshard, pilcrow, parsed, colorusers, granularity
				
				
				@parsed = parsed
				@title = "#{article} - Wiki blame"
				
				@time = Benchmark.realtime {
					@css, @legendhtml, @articlehtml = blame.blame
				}
				
				
				render :diff
			end
		end
	end
	
	module Views
		def layout
			html do
				head do
					meta charset:'utf-8'
					title @title
				end
				body do
					yield
				end
			end
		end
		
		def _input text, name, default=''
			label text, :for=>name
			input name:name, id:name, value:default
		end
		
		# options: {value => label}
		def _radio text, name, options, checked=0
			label text, :for=>name
			options.each_pair do |val, text|
				input name:name, type:'radio', value:val, id:"radio-#{name}-#{val}"
				label text, :for=>"radio-#{name}-#{val}"
			end
		end
		
		def _checkbox text, name, checked=false
			label text, :for=>name
			input name:name, id:name, type:'checkbox', checked:(!!checked)
		end
		
		def index
			form action:'/diff', method:'get' do
				ul do
					li{ _input 'Wiki language code: ', :lang, 'pl' }
					li{ _input 'Article name: ', :article }
				end
				
				ul do
					li{ _checkbox 'Exclude reverts? ', :reverts, true }
					li{ _checkbox 'Exclude reverts *hard*? (Compare every two revisions) ', :revertshard, true }
					li{ _checkbox 'Collapse subsequent revisions by the same user? ', :collapse, true }
					li{ _checkbox 'Assign unique colors to users instead of revisions? ', :colorusers, false }
					li{ _radio 'Diff granularity: ', :granularity, {
						chars: ' characters ', words: ' words ', lines: ' lines ' }
					}
				end
				
				ul do
					li{ _checkbox 'Show parsed HTML instead of wikitext? (Warning: may break stuff) ', :parsed, false }
					li{ _checkbox 'Insert pilcrow at newlines? ', :pilcrow, false }
				end
				
				input type:'submit'
				
				p "WikiBlame v 0.3 by Matma Rex (matma.rex@gmail.com). Released under CC-BY-SA 3.0."
				p{
					a 'Read the source',      :href=>R(SourceX, 'wikiblame.rb')
					text ", "
					a 'view the README',    :href=>R(SourceX, 'README')
					text "."
				}
				p{a 'See me on Github!', :href=>'https://github.com/MatmaRex/wikiblame'}
			end
		end
		
		def diff
			# do something with @css...
			
			div style:'border:1px solid black; margin:5px; padding:5px; float:right' do
				text! @legendhtml
				
				br; br
				text "Rendered in #{@time.round 2} seconds."
			end
			
			div style:(@parsed ? '' : 'white-space:pre-wrap; font-family:monospace') do
				text! @articlehtml
			end
		end
	end
end

class WikiBlame
	def initialize lang, article, reverts, collapse, revertshard, pilcrow, parsed, colorusers, granularity
		@lang, @article, @reverts, @collapse, @revertshard, @pilcrow, @parsed, @colorusers, @granularity = lang, article, reverts, collapse, revertshard, pilcrow, parsed, colorusers, granularity
	end
	
	def get_colors n
		# generate mostly unique colors, based on their hue
		if n<=9
			# 1 shade for each hue
			hues = n
			colors = (1..hues).map{|i| (i.to_f/hues*360).floor} # calculate the hues; from 1, so we do not "wrap over" the wheel

			colors = colors.map{|hue| "hsl(#{hue}, 100%, 35%)"}
		else
			# allow 3 shades for each hue
			hues = (n.to_f / 3).ceil # make sure there is just enough
			colors = (1..hues).map{|i| (i.to_f/hues*360).floor} # calculate the hues; from 1, so we do not "wrap over" the wheel

			colors = colors.map{|c| [[c, 35], [c, 55], [c, 75]]}.flatten.each_slice(2).to_a # convert each hue to three hue-lightness pairs
			colors = colors.map{|hue, lightness| "hsl(#{hue}, 100%, #{lightness}%)"}
		end
		
		colors[0...n]
	end
	
	def html_escape text
		text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
	end
	
	def blame
		s = Sunflower.new @lang+'.wikipedia.org'
		s.warnings = false
		s.log = false

		versions = s.API("action=query&prop=revisions&titles=#{CGI.escape @article}&rvlimit=500&rvprop=#{CGI.escape "#{@parsed ? '' : 'content|'}timestamp|user|comment|ids"}&rvdir=newer")
		versions = versions['query']['pages'].values[0]['revisions']
		versions = versions.map do |r| 
			Version[
				(r['*'] || "<hidden>"), 
				(r['user'] || "<hidden>"), 
				r['timestamp'], 
				(r['comment'] || "<hidden>"),
				nil,
				nil,
				r['revid']
			]
		end
		
		
		if @parsed
			# retrieve parsed HTML of each revision - we need to do it for each separately
			versions.each do |v|
				resp = s.API("action=parse&oldid=#{v.revid}&prop=text&disablepp=1&format=jsonfm")
				v.text = resp['parse']['text']['*']
			end
		end
		
		
		if @revertshard
			# compare every two, starting with longest spans - if the same, mark all inbetween as reverts
			(versions.length).downto(2) do |len| # downto(2) means we also handle "edits" with no changes - like page moves
				versions.each_cons(len).with_index do |cons, i|
					if cons[0].text == cons[-1].text # we have a revert!
						cons[1...cons.length].each{|v| v.revert = true} # mark as reverts
					end
				end
			end
		elsif @reverts
			# only compare consecutive
			versions.each_cons 3 do |a, b, a_again|
				if a.text == a_again.text # we have a revert!
					b.revert = a_again.revert = true # mark as reverts
				end
			end
		end
		
		if @collapse
			versions.each_cons 2 do |pv, nv|
				if pv.user == nv.user and !pv.revert and !nv.revert # ignore reverts
					pv.delete_me = true
					nv.replace Version[
						nv.text,
						nv.user,
						[pv.timestamp, nv.timestamp].join(", "),
						[pv.comment, nv.comment].join("; ")
					]
				end
			end
			
			versions.delete_if{|v| v.delete_me}
		end
		
		
		if @colorusers
			# each user has unique color
			userslist = versions.select{|v| !v.revert}.map{|v| v.user}.uniq
			colors = get_colors userslist.length-1
			colors.unshift 'white' # for the base revision
			
			user_to_color = Hash[ userslist.zip(colors) ]

			versions.each do |v|
				if v.revert
					v.color = 'grey' # reverts are grey
				else
					v.color = user_to_color[v.user]
				end
			end
		else
			# each revision has unique color
			colors = get_colors(versions.count{|v| !v.revert}-1) # dont count reverts
			colors.unshift 'white' # for the base revision
		
			versions.each do |v|
				if v.revert
					v.color = 'grey' # reverts are grey
				else
					v.color = colors.shift
				end
			end
		end
		
		massage = lambda{|text|
			ary = case @granularity
			when 'chars'; text.split('')
			when 'words'; text.split(/\b/)
			when 'lines'; text.split(/(?<=\n)/)
			end
			ary.map{|a| (@parsed ? a : html_escape(a)).gsub(/\r?\n/, "#{@pilcrow ? '&para;' : ''}\n") }
		}
		
		data = PatchRecorder.new massage.call versions[0].text

		(versions.length-1).times do |i|
			next if versions[i].revert # don't start from reverts
			
			j = i+1
			j += 1 until !versions[j] or !versions[j].revert # and don't finish at them
			next if !versions[j] # latest revisions were reverts
			
			d = Diff::LCS.diff massage.call(versions[i].text), massage.call(versions[j].text)
			data = data.patch d, versions[j].color
		end
		
		legendhtml = 
			"Legend (#{versions.length} revisions shown):<br>\n" +
			versions.map{|v| 
				"<span style='background:#{v.color}; color:#{foreground_for v.color}'>" + 
					"#{html_escape v.user} at #{html_escape v.timestamp}, comment: #{html_escape v.comment} (#{v.color})" + 
				"</span>"
			}.join("<br>\n") # yay superfluous indentation!
		
		articlehtml = data.output_marks.join('')
		
		css = '' # TODO
		
		return [css, legendhtml, articlehtml]
	end
end



def foreground_for color
	color =~ / (\d+)%\)/
	return 'black' if !$1 # doesn't match hsl scheme
	$1.to_i<=35 ? 'white' : 'black'
end

class Version < Array
	def text; self[0]; end
	def user; self[1]; end
	def timestamp; self[2]; end
	def comment; self[3]; end
	def color; self[4]; end
	def revert; self[5]; end
	def revid; self[6]; end
	
	def text=a; self[0]=a; end
	def user=a; self[1]=a; end
	def timestamp=a; self[2]=a; end
	def comment=a; self[3]=a; end
	def color=a; self[4]=a; end
	def revert=a; self[5]=a; end
	def revid=a; self[6]=a; end
end

class Mark < Array
	def index; self[0]; end
	def color; self[1]; end
	def length; self[2]; end
	def i; self[3]; end
	
	def index=a; self[0]=a; end
	def color=a; self[1]=a; end
	def length=a; self[2]=a; end
	def i=a; self[3]=a; end
	
	def inspect
		"<Mark index=#{index} length=#{length} color=#{color}>"
	end
	alias to_s inspect
end

class Object
	attr_accessor :delete_me
end

class PatchRecorder < Array
	attr_reader :marks

	def initialize *args
		super
		@marks = []
		self.add_mark 0, 'white', self.length
	end

	def add_mark index, color, length
		@marks<<Mark[index, color, length]
		return @marks.length-1
	end

	def remove_mark id
		@marks.delete id
	end
	
	def nudge_marks length, index, type
		if type==:-
			@marks.each do |m|
				if m.index>=index # m starts after removed part's start
					if m.index>index+length # m is all after removed part
						m.index-=length # so move it back
					else # m.index<=index+length - removed part ends in m
						m.length-=index+length-m.index # shorten it
						m.index=index # and nudge beginning to proper position
					end
				else # m.index<index - m starts before removed part's start
					if m.index+m.length<=index # m is all before removed part
						# do nothing
					else # m.index+m.length>index - removed part starts in m
						m.length-=length # so shorten it
					end
				end
			end
		else
			@marks.each do |m|
				if m.index>=index # m starts after added part's start
					if m.index>index+length # m is all after added part
						m.index+=length # so move it forward
					else # m.index<=index+length - added part ends in m
						m.index+=length # so move it forward
					end
				else # m.index<index - m starts before added part's start
					if m.index+m.length<=index # m is all before added part
						# do nothing
					else # m.index+m.length>index - added part starts in m
						m.length+=length # so lengthen it
					end
				end
			end
		end
		
		@marks.delete_if{|m| m.length<1 or m.index<0}
	end
	
	def normalize_marks!
		# kill null marks
		@marks.delete_if{|m| m.length<1 or m.index<0}
		
		# add original index info
		@marks.each_with_index{|m, i| m.i=i}
		
		# sort marks by positions
		@marks=@marks.sort_by{|m| [m.index, -m.length] }
		
		normalize_marks_overlap
		
		# resort in original order
		@marks=@marks.sort_by{|m| m.i}
	end
	# if two marks overlap, split one of them
	def normalize_marks_overlap
		i = 0
		while i < @marks.length - 1
			earlier, later = @marks[i], @marks[i+1]
			# if earlier overlaps later, split it in two
			if earlier.index+earlier.length > later.index
				@marks[i, 2] = [
					Mark[ earlier.index, earlier.color, later.index-earlier.index, earlier.i ],
					later,
					Mark[ later.index+later.length, earlier.color,  earlier.length-(later.length)-(later.index-earlier.index), earlier.i  ],
				]
				
				# we have to re-sort the entire thing from this point on... (tested)
				@marks[i..-1] = @marks[i..-1].sort_by{|m| [m.index, -m.length] }
				
			end
			
			i += 1
		end
	end
	
	def output_marks
		normalize_marks!
		
		# figure out where do we want to place the spans, and in what order
		inserts=[]
		@marks.each do |index, color, length|
			inserts[index]=[] unless inserts[index]
			inserts[index+length]=[] unless inserts[index+length]
			
			inserts[index].push "<span style='background:#{color}; color:#{foreground_for color}'>"
			inserts[index+length].unshift '</span>'
		end
		
		# and actually place them - in reverse, so we don't have to worry about inserts moving the text
		s = self.clone # we don't want to insert marks in self
		
		# doesn't work - indices start from 0, not from n
		# inserts.reverse_each.with_index do |arr, i|
		
		(inserts.length-1).downto(0) do |i|
			arr = inserts[i]
			next if !arr or arr.empty?
			
			s[i, 0] = [arr.join('')]
		end
		
		return s
	end
	
	# collapse consecutive with the same color if possible
	def normalize_marks_collapse
		# return
		i = 0
		while i < @marks.length - 1
			a, b = @marks[i], @marks[i+1]
			if a.index+a.length == b.index and a.color == b.color
				new = a.dup
				new.length += b.length
				
				@marks[i, 2] = [new]
				i += 1
				# normalize_marks_overlap
			else
				i += 1
			end
		end
	end
	
	def patch diffs, color
		adds=[]
		removes=[]
		
		diffs.flatten.map{|d| d.to_a}.each do |type, index, text|
			case type.to_sym
			when :-
				removes<<[index, text]
			when :+
				adds<<[index, text]
			else
				raise 'Unknown diff type: '+type.to_s
			end
		end
		
		removes.reverse_each do |index, text|
			raise "Actual text not matching diff data when deleting - #{self[index].inspect} vs #{text.inspect}" if self[index]!=text
			
			self.delete_at index
			self.nudge_marks 1, index, :-
		end
		normalize_marks_collapse
		
		adds.each do |index, text|
			self[index, 0] = text
			self.nudge_marks 1, index, :+
			self.add_mark index, color, 1
		end
		normalize_marks_collapse
		
		return self
  end
end



